class Admin::MediumController < Admin::BaseController
  # Uploading, deleting, or renaming media changes the browse-page backlinks.
  after_action :invalidate_media_usage_index, only: %i[create destroy bulk_destroy rename]

  def picker
    @media_type = params[:media_type] || "images"
    # Who opened the picker. "gallery" means the gallery builder did, and the
    # selection goes back to it instead of being written into the document —
    # so the label says that rather than "Insert Selected".
    @picker_for = params[:for].presence
    @media = Medium.originals_only
                   .where(media_type: @media_type)
                   .order(created_at: :desc)
    render layout: false
  end

  def browse
    # Load only original media files (exclude variants)
    @media = Medium.originals_only
                   .order(created_at: :desc)

    # Reverse index of everything that references each media file — posts,
    # pages, documentation, products, and config files — keyed by path.
    @media_usages = MediaUsageIndex.fetch

    # Only surface the Global tab when there's actually global (config-
    # referenced) media to show — same "show if it exists" rule as the
    # type tabs.
    @has_global_media = @media.any? { |m| @media_usages[m.file_path].any? { |u| u[:global] } }

    # Get distinct media types that exist
    @existing_types = Medium.distinct.pluck(:media_type).compact

    render layout: "admin"
  end

  # Uploads run one file per request from the browse page (see the
  # media-upload Stimulus controller), which keeps the user on the page and
  # surfaces per-file results. Each single-file upload is fast (write + async
  # variant queue), so there's no batch job / progress page anymore. The HTML
  # branch is a synchronous no-JS fallback.
  def create
    files = params[:files]
    uploaded_files = if files.is_a?(Array)
      files.reject(&:blank?)
    elsif files.present?
      [ files ]
    elsif params[:file].present?
      [ params[:file] ]
    else
      []
    end

    if uploaded_files.empty?
      respond_to do |format|
        format.json { render json: { success: false, error: "No files selected" }, status: :unprocessable_entity }
        format.html { redirect_to browse_admin_medium_index_path, alert: "No files selected" }
      end
      return
    end

    respond_to do |format|
      # JS path: one file per request → return the rendered card (or a clear error).
      format.json do
        @conversion_notice = nil
        begin
          medium = process_single_upload(uploaded_files.first)
          ImageVariantGenerator.queue_baseline!(medium.file_path) if medium.image?
          render json: {
            success: true,
            media_id: medium.id,
            filename: File.basename(medium.file_path),
            path: medium.file_path,
            message: @conversion_notice,
            card_html: render_to_string(partial: "admin/medium/media_card", formats: [ :html ], locals: { media: medium, usages: [] })
          }
        rescue => e
          render json: { success: false, error: e.message, filename: uploaded_files.first&.original_filename }, status: :unprocessable_entity
        end
      end

      # No-JS fallback: process each synchronously, redirect with a summary.
      format.html do
        notices, errors = [], []
        uploaded_files.first(50).each do |file|
          @conversion_notice = nil
          begin
            medium = process_single_upload(file)
            ImageVariantGenerator.queue_baseline!(medium.file_path) if medium.image?
            notices << (@conversion_notice || "#{File.basename(medium.file_path)} uploaded")
          rescue => e
            errors << "#{file.original_filename}: #{e.message}"
          end
        end
        flash[:notice] = notices.join(" · ") if notices.any?
        flash[:alert]  = errors.join(" · ") if errors.any?
        redirect_to browse_admin_medium_index_path
      end
    end
  end

  def clear_failed_jobs
    if Rails.env.development?
      SolidQueue::FailedExecution
        .joins("INNER JOIN solid_queue_jobs ON solid_queue_jobs.id = solid_queue_failed_executions.job_id")
        .where("solid_queue_jobs.class_name = ?", "GenerateImageVariantsJob")
        .destroy_all
    end

    redirect_to browse_admin_medium_index_path, notice: "Cleared failed jobs"
  end

  def queue_missing_variants
    # Only queue missing variants in development
    # Production generates variants on upload
    unless Rails.env.development?
      redirect_to browse_admin_medium_index_path, notice: "Variant queueing only available in development"
      return
    end

    queued = 0

    Medium.images.originals_only.find_each do |medium|
      path = File.join(RoeSitePaths::SITE_PATH, medium.file_path.sub(%r{^/}, ""))

      next unless File.exist?(path)
      next if ImageVariantGenerator.variants_exist?(path)

      queued += 1 if ImageVariantGenerator.queue!(medium.file_path)
    end

    redirect_to browse_admin_medium_index_path, notice: "Queued #{queued} #{'image'.pluralize(queued)} for optimization"
  end

  # Reclaim disk by reducing the variant cache to what's needed: unused
  # images drop to their baseline, orphaned variants are removed, in-use
  # images keep their full set. Safe — anything pruned regenerates on
  # demand. Runs against the current environment's filesystem, so on prod
  # it prunes prod.
  def prune_variants
    deleted = ImageVariantGenerator.prune_all!
    redirect_to browse_admin_medium_index_path,
                notice: "Pruned #{deleted} variant #{'file'.pluralize(deleted)}. Unused images reduced to baseline; in-use kept (rebuilds on demand)."
  end

  def regenerate_variants
    medium = Medium.find(params[:id])

    unless medium.image?
      redirect_to browse_admin_medium_index_path, alert: "Only images can have variants generated"
      return
    end

    path = File.join(RoeSitePaths::SITE_PATH, medium.file_path.sub(%r{^/}, ""))

    unless File.exist?(path)
      redirect_to browse_admin_medium_index_path, alert: "Image file not found on disk"
      return
    end

    # Explicit user-initiated regenerate — bypass dedup so we definitely
    # enqueue fresh, even if a prior job's flag is still warm in the cache.
    ImageVariantGenerator.queue!(medium.file_path, force: true)

    redirect_to browse_admin_medium_index_path, notice: "Queued variant generation for #{File.basename(medium.file_path)}"
  end

  def destroy
    media = Medium.find(params[:id])
    full_path = File.join(RoeSitePaths::SITE_PATH, media.file_path.to_s.sub(%r{^/}, ""))

    # Delete file from filesystem
    File.delete(full_path) if File.exist?(full_path)

    # Delete database record (variants deleted via before_destroy callback)
    media.destroy

    redirect_to browse_admin_medium_index_path(type: params[:type]), notice: "File deleted"
  end

  def bulk_destroy
    media_ids = params[:media_ids] || []

    if media_ids.empty?
      redirect_to browse_admin_medium_index_path, alert: "No files selected"
      return
    end

    deleted_count = 0
    errors = []

    media_ids.each do |id|
      media = Medium.find_by(id: id)
      next unless media

      begin
        full_path = File.join(RoeSitePaths::SITE_PATH, media.file_path.to_s.sub(%r{^/}, ""))
        File.delete(full_path) if File.exist?(full_path)
        media.destroy
        deleted_count += 1
      rescue => e
        errors << "Failed to delete #{File.basename(media.file_path)}: #{e.message}"
      end
    end

    if errors.any?
      redirect_to browse_admin_medium_index_path,
                  alert: "Deleted #{deleted_count} files. Errors: #{errors.join(', ')}"
    else
      redirect_to browse_admin_medium_index_path,
                  notice: "Deleted #{deleted_count} #{'file'.pluralize(deleted_count)}"
    end
  end

  def rename
    @medium = Medium.find(params[:id])
    new_filename = sanitize_media_filename(params[:new_filename])

    if new_filename.blank?
      flash[:error] = "Filename cannot be empty"
      redirect_to browse_admin_medium_index_path and return
    end

    old_file_path = @medium.file_path                       # e.g. "/media/images/foo.jpg"
    relative_path = old_file_path.delete_prefix("/")
    old_path = File.join(RoeSitePaths::SITE_PATH, relative_path)
    extension = File.extname(old_path)
    media_type = determine_media_type(extension.delete_prefix("."))

    # Keep the file in its current directory (File.join, not the String's
    # non-existent #dirname). Derive the new web path from the old one's
    # directory so it works regardless of folder.
    new_path = File.join(File.dirname(old_path), "#{new_filename}#{extension}")
    new_file_path = File.join(File.dirname(old_file_path), "#{new_filename}#{extension}")

    if File.exist?(new_path) && new_path != old_path
      flash[:error] = "A file with that name already exists"
      redirect_to browse_admin_medium_index_path and return
    end

    begin
      File.rename(old_path, new_path)
      # Images carry responsive variants (variants/<base>-<size>.<ext> plus
      # .webp siblings) that must move with the original or they orphan.
      rename_image_variants(old_path, new_path) if media_type == "images"
      @medium.update(file_path: new_file_path)

      # A rename would otherwise break every link to the old path, so rewrite
      # references across content and config to point at the new name.
      rewritten = MediaReferenceRewriter.rewrite(old_file_path, new_file_path)
      MediaUsageIndex.invalidate!

      notice = "Renamed to #{new_filename}#{extension}"
      notice += ". Updated #{rewritten} #{'reference'.pluralize(rewritten)}." if rewritten.positive?
      flash[:notice] = notice
    rescue => e
      flash[:error] = "Failed to rename: #{e.message}"
    end

    redirect_to browse_admin_medium_index_path(type: media_type)
  end

  # Rename an image's generated variant files to match the new base name.
  def rename_image_variants(old_path, new_path)
    ImageVariantGenerator::VARIANTS.each_key do |variant|
      old_variant = ImageVariantGenerator.variant_path_for(old_path, variant)
      new_variant = ImageVariantGenerator.variant_path_for(new_path, variant)
      rename_if_present(old_variant, new_variant)
      # WebP sibling emitted alongside each variant.
      rename_if_present(
        old_variant.sub(File.extname(old_variant), ".webp"),
        new_variant.sub(File.extname(new_variant), ".webp")
      )
    end
  end

  def rename_if_present(from, to)
    File.rename(from, to) if File.exist?(from)
  end
  private :rename_image_variants, :rename_if_present

  def duration
    media_path = params[:path]

    unless media_path.present?
      render json: { error: "Missing path parameter" }, status: :bad_request
      return
    end

    # Convert /media/audio/file.mp3 to absolute path (as STRING)
    file_path = File.join(RoeSitePaths::SITE_PATH, media_path.delete_prefix("/")).to_s  # ← Add .to_s

    unless File.exist?(file_path)
      render json: { error: "File not found" }, status: :not_found
      return
    end

    duration = MediaDurationExtractor.extract(file_path)

    if duration
      render json: { duration: duration }
    else
      render json: { error: "Could not extract duration" }, status: :unprocessable_entity
    end
  end

  # Used by the metadata editor and publish modal to warn when a media
  # path in a post's metadata doesn't resolve to a real file on disk.
  # Only validates /media/* paths (external URLs are treated as present).
  def exists
    media_path = params[:path].to_s.strip

    if media_path.empty?
      render json: { exists: true, checked: false }
      return
    end

    unless media_path.start_with?("/media/")
      render json: { exists: true, checked: false }
      return
    end

    file_path = File.join(RoeSitePaths::SITE_PATH, media_path.delete_prefix("/")).to_s
    render json: { exists: File.exist?(file_path), checked: true, path: media_path }
  end

  # Re-render a single media card so the browse page can live-update a card
  # whose image variants are still processing (the media-upload controller
  # polls this until `pending` is false, then stops).
  def card
    medium = Medium.find(params[:id])
    usages = MediaUsageIndex.fetch[medium.file_path] || []
    # "Pending" tracks the cheap baseline preview, not the whole ladder —
    # so the grid's poll stops as soon as the thumbnail is servable
    # (the rest of the variants build on-demand at render).
    pending = medium.image? && ImageVariantGenerator.available? && !medium.baseline_ready?
    render json: {
      pending: !!pending,
      card_html: render_to_string(partial: "admin/medium/media_card", formats: [ :html ], locals: { media: medium, usages: usages })
    }
  end

  private

  # Formats that aren't web-friendly but that we can transcode to WebP on the
  # way in (so the stored original is web-ready). Requires libvips; if it's not
  # available we reject with a clear message instead of storing something the
  # browser can't render.
  CONVERT_TO_WEBP = %w[tiff tif heic heif].freeze

  def process_single_upload(uploaded_file)
    original_ext = File.extname(uploaded_file.original_filename).delete_prefix(".").downcase
    convert = CONVERT_TO_WEBP.include?(original_ext)

    if convert
      unless ImageVariantGenerator.available?
        raise "#{original_ext.upcase} images aren't well supported on the web. Please upload a JPG, PNG, WebP, or GIF instead."
      end
      media_type = "images"
      extension_with_dot = ".webp"
    else
      media_type = determine_media_type(original_ext)
      extension_with_dot = File.extname(uploaded_file.original_filename)
    end

    folder_path = Pathname.new(File.join(RoeSitePaths::SITE_PATH, "media/#{media_type}"))
    FileUtils.mkdir_p(folder_path)

    base_name = File.basename(uploaded_file.original_filename, File.extname(uploaded_file.original_filename))
    sanitized_base = sanitize_media_filename(base_name)
    filename = "#{sanitized_base}#{extension_with_dot}"

    # Check for duplicates
    counter = 1
    while Medium.exists?(file_path: "/media/#{media_type}/#{filename}")
      filename = "#{sanitized_base}-#{counter}#{extension_with_dot}"
      counter += 1
    end

    file_path = folder_path.join(filename)

    if convert
      begin
        require "image_processing/vips"
        ImageProcessing::Vips
          .source(uploaded_file.tempfile.path)
          .convert("webp")
          .saver(quality: ImageVariantGenerator::WEBP_QUALITY)
          .call(destination: file_path.to_s)
      rescue => e
        Rails.logger.error "[Upload] #{original_ext} → webp failed: #{e.class} #{e.message}"
        raise "#{original_ext.upcase} images aren't well supported on the web, and this one couldn't be converted. Please upload a JPG, PNG, WebP, or GIF instead."
      end
      @conversion_notice = "Converted #{base_name}.#{original_ext} → #{filename} for better web support."
    else
      File.open(file_path, "wb") { |file| file.write(uploaded_file.read) }
    end

    # Create database record
    relative_path = "/media/#{media_type}/#{filename}"
    Medium.create!(
      file_path: relative_path,
      media_type: media_type,
      uploaded_at: Time.current
    )
  end

  def determine_media_type(extension)
    ext = extension.downcase

    case ext
    when "png", "jpg", "jpeg", "webp", "gif", "svg", "bmp"
      "images"
    when "mp3", "m4a", "wav", "ogg", "flac", "aac"
      "audio"
    when "mp4", "webm", "ogv", "mov", "avi", "mkv"
      "video"
    when "woff", "woff2", "ttf", "otf"
      "fonts"
    else
      # Fail loudly rather than silently misclassifying. Previously this
      # returned "images" so a .pdf upload would land at /media/images/
      # with media_type: "images" — wrong data quietly persisted to the
      # DB and exposed in the picker. Better to surface the gap to the
      # user. Tracked for 0.0.2: see "other" bucket scope discussion.
      raise "Unsupported file type: .#{ext}. Roe currently supports images (jpg/png/gif/webp/svg/bmp), audio (mp3/m4a/wav/ogg/flac/aac), video (mp4/webm/ogv/mov/avi/mkv), and fonts (woff/woff2/ttf/otf)."
    end
  end

  def sanitize_media_filename(filename)
    basename = File.basename(filename, ".*")

    # Convert to lowercase, replace spaces/special chars with hyphens
    basename.downcase
            .gsub(/[^a-z0-9\-_]/, "-")
            .gsub(/-+/, "-")
            .strip
            .gsub(/^-|-$/, "")
  end
end
