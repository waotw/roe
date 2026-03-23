class Admin::MediumController < Admin::BaseController
  def browse
    @media = Medium.where(media_type: 'images').order(uploaded_at: :desc)
  end

  def create
    uploaded_file = params[:file]

    media_type = 'images'
    folder_path = Rails.root.join("site/media/#{media_type}")
    FileUtils.mkdir_p(folder_path)

    # Extract extension FIRST, before sanitizing
    extension = File.extname(uploaded_file.original_filename)
    base_name = File.basename(uploaded_file.original_filename, extension)

    # Sanitize only the base name (without extension)
    sanitized_base = sanitize_media_filename(base_name)
    filename = "#{sanitized_base}#{extension}"

    # Check for duplicates
    counter = 1
    while Medium.exists?(file_path: "/media/#{media_type}/#{filename}")
      filename = "#{sanitized_base}-#{counter}#{extension}"
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

    respond_to do |format|
      format.json { render json: { success: true, path: relative_path } }
      format.html { redirect_to browse_admin_medium_index_path, notice: "Image uploaded" }
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

    redirect_to browse_admin_medium_index_path, notice: "Image deleted"
  end

  def rename
    @medium = Medium.find(params[:id])
    new_filename = sanitize_media_filename(params[:new_filename])

    if new_filename.blank?
      flash[:error] = "Filename cannot be empty"
      redirect_to browse_admin_medium_index_path and return
    end

    # Use site/media/images instead of public
    relative_path = @medium.file_path.delete_prefix('/')
    old_path = Rails.root.join('site', relative_path)
    extension = File.extname(old_path)
    new_path = old_path.dirname.join("#{new_filename}#{extension}")

    Rails.logger.info "Old path: #{old_path}"
    Rails.logger.info "File exists? #{File.exist?(old_path)}"

    if File.exist?(new_path) && new_path != old_path
      flash[:error] = "A file with that name already exists"
      redirect_to browse_admin_medium_index_path and return
    end

    begin
      File.rename(old_path, new_path)
      # The file_path in DB stays the same pattern, just new filename
      new_file_path = "/media/images/#{new_filename}#{extension}"
      @medium.update(file_path: new_file_path)

      flash[:notice] = "Renamed to #{new_filename}#{extension}"
    rescue => e
      flash[:error] = "Failed to rename: #{e.message}"
    end

    redirect_to browse_admin_medium_index_path
  end

  private

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
