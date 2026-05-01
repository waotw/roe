class Admin::MediumController < Admin::BaseController
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
                   .includes(:posts)
                   .order(created_at: :desc)

    # Get distinct media types that exist
    @existing_types = Medium.distinct.pluck(:media_type).compact

    render layout: 'application'
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

      # Create batch and save files to temp directory
      batch_id = SecureRandom.uuid
      temp_dir = Rails.root.join("tmp", "uploads", batch_id)
      FileUtils.mkdir_p(temp_dir)

      # Save uploaded files temporarily and track their info
      temp_files = uploaded_files.map do |file|
        temp_path = temp_dir.join(file.original_filename)
        File.open(temp_path, 'wb') { |f| f.write(file.read) }

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
        media_type: determine_media_type_from_files(uploaded_files)
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
      if medium.image? && ImageVariantGenerator.available?
        GenerateImageVariantsJob.perform_later(medium.file_path, nil)
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

    unless @batch && @batch['id'] == @batch_id
      redirect_to browse_admin_medium_index_path, alert: "Upload session not found"
      nil
    end
  end

  def clear_failed_jobs
    if Rails.env.development?
      SolidQueue::FailedExecution
        .joins("INNER JOIN solid_queue_jobs ON solid_queue_jobs.id = solid_queue_failed_executions.job_id")
        .where("solid_queue_jobs.class_name = ?", 'GenerateImageVariantsJob')
        .destroy_all
    end

    redirect_to browse_admin_medium_index_path, notice: "Cleared failed jobs"
  end

  def queue_missing_variants
    queued = 0

    Medium.images.originals_only.find_each do |medium|
      path = File.join(RoeSitePaths::SITE_PATH, medium.file_path.sub(%r{^/}, ""))

      next unless File.exist?(path)
      next if ImageVariantGenerator.variants_exist?(path)

      GenerateImageVariantsJob.perform_later(medium.file_path, nil)
      queued += 1
    end

    redirect_to browse_admin_medium_index_path, notice: "Queued #{queued} #{'image'.pluralize(queued)} for optimization"
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

    relative_path = @medium.file_path.delete_prefix('/')
    old_path = File.join(RoeSitePaths::SITE_PATH, relative_path)
    extension = File.extname(old_path)

    # Keep same media type folder
    media_type = determine_media_type(extension.delete_prefix('.'))
    new_path = old_path.dirname.join("#{new_filename}#{extension}")

    if File.exist?(new_path) && new_path != old_path
      flash[:error] = "A file with that name already exists"
      redirect_to browse_admin_medium_index_path and return
    end

    begin
      File.rename(old_path, new_path)
      new_file_path = "/media/#{media_type}/#{new_filename}#{extension}"
      @medium.update(file_path: new_file_path)

      flash[:notice] = "Renamed to #{new_filename}#{extension}"
    rescue => e
      flash[:error] = "Failed to rename: #{e.message}"
    end

    redirect_to browse_admin_medium_index_path(type: media_type)
  end

  def duration
    media_path = params[:path]

    unless media_path.present?
      render json: { error: 'Missing path parameter' }, status: :bad_request
      return
    end

    # Convert /media/audio/file.mp3 to absolute path (as STRING)
    file_path = File.join(RoeSitePaths::SITE_PATH, media_path.delete_prefix('/')).to_s  # ← Add .to_s

    unless File.exist?(file_path)
      render json: { error: 'File not found' }, status: :not_found
      return
    end

    duration = MediaDurationExtractor.extract(file_path)

    if duration
      render json: { duration: duration }
    else
      render json: { error: 'Could not extract duration' }, status: :unprocessable_entity
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

    unless media_path.start_with?('/media/')
      render json: { exists: true, checked: false }
      return
    end

    file_path = File.join(RoeSitePaths::SITE_PATH, media_path.delete_prefix('/')).to_s
    render json: { exists: File.exist?(file_path), checked: true, path: media_path }
  end

  private

  def process_single_upload(uploaded_file)
    # Your existing upload logic, extracted to a method
    extension = File.extname(uploaded_file.original_filename).delete_prefix('.')
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
    File.open(file_path, 'wb') do |file|
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
    first_ext = File.extname(files.first.original_filename).delete_prefix('.')
    determine_media_type(first_ext)
  end

  def determine_media_type(extension)
    ext = extension.downcase

    case ext
    when 'png', 'jpg', 'jpeg', 'webp', 'gif', 'svg', 'bmp'
      'images'
    when 'mp3', 'm4a', 'wav', 'ogg', 'flac', 'aac'
      'audio'
    when 'mp4', 'webm', 'ogv', 'mov', 'avi', 'mkv'
      'video'
    when 'woff', 'woff2', 'ttf', 'otf'
      'fonts'
    else
      'images'  # default fallback
    end
  end

  def sanitize_media_filename(filename)
    basename = File.basename(filename, '.*')

    # Convert to lowercase, replace spaces/special chars with hyphens
    basename.downcase
            .gsub(/[^a-z0-9\-_]/, '-')
            .gsub(/-+/, '-')
            .strip
            .gsub(/^-|-$/, '')
  end
end
