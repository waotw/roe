class Admin::MediumController < Admin::BaseController
  # Uploading, deleting, or renaming media changes the browse-page backlinks.
  after_action :invalidate_media_usage_index, only: %i[create destroy bulk_destroy rename]

  def picker
    @media_type = params[:media_type] || "images"
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

  def create
    files = params[:files]

    # Handle both single file and multiple files
    uploaded_files = if files.is_a?(Array)
      files.reject(&:blank?)  # Add this to filter out empty strings
    elsif files.present?
      [ files ]
    elsif params[:file].present?
      [ params[:file] ]
    else
      []
    end

    if uploaded_files.empty?
      redirect_to browse_admin_medium_index_path, alert: "No files selected"
      return
    end

    # If more than one file, go to bulk upload page
    if uploaded_files.length > 1
      limit = Rails.env.production? ? 20 : 50
      if uploaded_files.length > limit
        redirect_to browse_admin_medium_index_path, alert: "Maximum #{limit} files allowed"
        return
      end

      # Resolve the batch's media type early. determine_media_type now
      # raises on unsupported extensions instead of misclassifying as
      # "images" — catch that here so the user gets a clear flash
      # instead of a stack trace, and so we abort before writing any
      # temp files or queueing a job for files we can't actually use.
      begin
        batch_media_type = determine_media_type_from_files(uploaded_files)
      rescue => e
        redirect_to browse_admin_medium_index_path, alert: "Upload failed: #{e.message}"
        return
      end

      # Create batch and save files to temp directory
      batch_id = SecureRandom.uuid
      temp_dir = Rails.root.join("tmp", "uploads", batch_id)
      FileUtils.mkdir_p(temp_dir)

      # Save uploaded files temporarily and track their info
      temp_files = uploaded_files.map do |file|
        temp_path = temp_dir.join(file.original_filename)
        File.open(temp_path, "wb") { |f| f.write(file.read) }

        {
          temp_path: temp_path.to_s,
          original_filename: file.original_filename,
          size: file.size
        }
      end

      # Store file data in session for the progress page
      session[:upload_batch] = {
        id: batch_id,
        files: temp_files.map { |f| { filename: f[:original_filename], size: f[:size] } },
        total: uploaded_files.length,
        media_type: batch_media_type
      }

      # Queue the uploads with temp file paths
      BulkUploadJob.perform_later(batch_id, temp_files)

      redirect_to upload_progress_admin_medium_index_path(batch_id: batch_id)
      return
    end

    # Single file - use existing logic
    uploaded_file = uploaded_files.first

    begin
      medium = process_single_upload(uploaded_file)
      media_type = medium.media_type

      # Generate variants if needed
      if medium.image? && ImageVariantGenerator.queue!(medium.file_path)
        notice_message = "#{media_type.singularize.capitalize} uploaded (optimizing in background)"
      else
        notice_message = "#{media_type.singularize.capitalize} uploaded"
      end

      respond_to do |format|
        format.json { render json: { success: true, path: medium.file_path, filename: File.basename(medium.file_path, ".*") } }
        format.html { redirect_to browse_admin_medium_index_path(type: media_type), notice: notice_message }
      end
    rescue => e
      respond_to do |format|
        format.json { render json: { success: false, error: e.message }, status: :unprocessable_entity }
        format.html { redirect_to browse_admin_medium_index_path, alert: "Upload failed: #{e.message}" }
      end
    end
  end

  def upload_progress
    @batch_id = params[:batch_id]
    @batch = session[:upload_batch]

    Rails.logger.info "=== UPLOAD PROGRESS DEBUG ==="
    Rails.logger.info "Params batch_id: #{@batch_id.inspect}"
    Rails.logger.info "Session upload_batch: #{@batch.inspect}"
    Rails.logger.info "Session keys: #{session.keys.inspect}"
    Rails.logger.info "Match? #{@batch && @batch[:id] == @batch_id}"

    unless @batch && @batch["id"] == @batch_id
      redirect_to browse_admin_medium_index_path, alert: "Upload session not found"
      return
    end

    # Check if uploads are already complete (fallback when Turbo Streams miss updates)
    @upload_status = check_upload_completion_status
  end

  # Checks if the batch upload job has completed by looking at:
  # 1. Whether the job is still in the queue
  # 2. Whether the expected media files exist in the database
  def check_upload_completion_status
    filenames = @batch["files"].map { |f| f["filename"] }

    # Build list of possible paths for each file (different media types + counter suffixes)
    possible_paths = []
    filename_patterns = []

    filenames.each do |name|
      base = File.basename(name, File.extname(name))
      ext = File.extname(name)
      # Match exact name or name with counter suffix (e.g., image.jpg or image-1.jpg)
      filename_patterns << "#{base}%#{ext}"

      # Also add exact paths for all media types
      possible_paths.concat([
        "/media/images/#{name}",
        "/media/audio/#{name}",
        "/media/video/#{name}"
      ])
    end

    # Check for exact matches first
    existing_exact = Medium.where(file_path: possible_paths).count

    # Check for files with counter suffixes using LIKE patterns
    existing_pattern = 0
    filename_patterns.each do |pattern|
      existing_pattern += 1 if Medium.where("file_path LIKE ?", "/media/%/#{pattern}").exists?
    end

    existing_count = [ existing_exact, existing_pattern ].max

    # Check if the bulk upload job is still running
    job_running = SolidQueue::Job.exists?(
      class_name: "BulkUploadJob",
      finished_at: nil
    )

    # Determine status
    if existing_count >= filenames.length && !job_running
      :complete
    elsif existing_count > 0
      :partial
    else
      :pending
    end
  end
  private :check_upload_completion_status

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

  private

  def process_single_upload(uploaded_file)
    # Your existing upload logic, extracted to a method
    extension = File.extname(uploaded_file.original_filename).delete_prefix(".")
    media_type = determine_media_type(extension)

    folder_path = Pathname.new(File.join(RoeSitePaths::SITE_PATH, "media/#{media_type}"))
    FileUtils.mkdir_p(folder_path)

    extension_with_dot = File.extname(uploaded_file.original_filename)
    base_name = File.basename(uploaded_file.original_filename, extension_with_dot)

    sanitized_base = sanitize_media_filename(base_name)
    filename = "#{sanitized_base}#{extension_with_dot}"

    # Check for duplicates
    counter = 1
    while Medium.exists?(file_path: "/media/#{media_type}/#{filename}")
      filename = "#{sanitized_base}-#{counter}#{extension_with_dot}"
      counter += 1
    end

    file_path = folder_path.join(filename)

    # Save file
    File.open(file_path, "wb") do |file|
      file.write(uploaded_file.read)
    end

    # Create database record
    relative_path = "/media/#{media_type}/#{filename}"
    Medium.create!(
      file_path: relative_path,
      media_type: media_type,
      uploaded_at: Time.current
    )
  end

  def determine_media_type_from_files(files)
    # Use the first file's extension to determine type
    first_ext = File.extname(files.first.original_filename).delete_prefix(".")
    determine_media_type(first_ext)
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
