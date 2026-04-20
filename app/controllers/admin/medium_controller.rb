class Admin::MediumController < Admin::BaseController
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
    uploaded_file = params[:file]

    # Determine media type from file extension
    extension = File.extname(uploaded_file.original_filename).delete_prefix('.')
    media_type = determine_media_type(extension)

    folder_path = Rails.root.join("site/media/#{media_type}")
    FileUtils.mkdir_p(folder_path)

    # Extract extension FIRST, before sanitizing
    extension_with_dot = File.extname(uploaded_file.original_filename)
    base_name = File.basename(uploaded_file.original_filename, extension_with_dot)

    # Sanitize only the base name (without extension)
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
    medium = Medium.create!(
      file_path: relative_path,
      media_type: media_type,  # Store normalized type (images/audio/video), not extension
      uploaded_at: Time.current
    )

    # After creating medium
    if medium.image? && ImageVariantGenerator.available?
      # Count recent uploads in last 5 minutes
      recent_uploads = Medium.where('created_at > ?', 5.minutes.ago).count

      if recent_uploads <= 5
        # Small batch - process immediately
        GenerateImageVariantsJob.perform_later(relative_path, nil)
        notice_message = "#{media_type.singularize.capitalize} uploaded (optimizing in background)"
      else
        # Large batch - will generate on-demand
        notice_message = "#{media_type.singularize.capitalize} uploaded (variants will generate on first view)"
      end
    else
      notice_message = "#{media_type.singularize.capitalize} uploaded"
    end

    respond_to do |format|
      format.json { render json: { success: true, path: relative_path } }
      format.html { redirect_to browse_admin_medium_index_path(type: media_type), notice: notice_message }
    end
  rescue => e
    respond_to do |format|
      format.json { render json: { success: false, error: e.message }, status: :unprocessable_entity }
      format.html { redirect_to browse_admin_medium_index_path, alert: "Upload failed: #{e.message}" }
    end
  end

  def destroy
    media = Medium.find(params[:id])
    full_path = Rails.root.join("site#{media.file_path}")

    # Delete file from filesystem
    File.delete(full_path) if File.exist?(full_path)

    # Delete database record
    media.destroy

    redirect_to browse_admin_medium_index_path(type: params[:type]), notice: "File deleted"
  end

  def rename
    @medium = Medium.find(params[:id])
    new_filename = sanitize_media_filename(params[:new_filename])

    if new_filename.blank?
      flash[:error] = "Filename cannot be empty"
      redirect_to browse_admin_medium_index_path and return
    end

    relative_path = @medium.file_path.delete_prefix('/')
    old_path = Rails.root.join('site', relative_path)
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
    file_path = Rails.root.join('site', media_path.delete_prefix('/')).to_s  # ← Add .to_s

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

  private

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
