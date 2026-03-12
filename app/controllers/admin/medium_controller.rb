class Admin::MediumController < Admin::BaseController
  def browse
    @media = Medium.where(media_type: 'images').order(uploaded_at: :desc)
  end

  def create
    uploaded_file = params[:file]

    media_type = 'images'
    folder_path = Rails.root.join("content/media/#{media_type}")
    FileUtils.mkdir_p(folder_path)

    # Sanitize filename
    filename = sanitize_media_filename(uploaded_file.original_filename)

    # Check for duplicates and append timestamp if needed
    base_name = File.basename(filename, File.extname(filename))
    extension = File.extname(filename)
    counter = 1

    while Medium.exists?(file_path: "/media/#{media_type}/#{filename}")
      filename = "#{base_name}-#{counter}#{extension}"
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
    full_path = Rails.root.join("content#{media.file_path}")

    # Delete file from filesystem
    File.delete(full_path) if File.exist?(full_path)

    # Delete database record
    media.destroy

    redirect_to browse_admin_medium_index_path, notice: "Image deleted"
  end

  private

  def sanitize_media_filename(filename)
    # Get extension
    ext = File.extname(filename)
    basename = File.basename(filename, ext)

    # Convert to lowercase, replace spaces/special chars with hyphens
    clean_name = basename.downcase.gsub(/[^a-z0-9\-_]/, '-').gsub(/-+/, '-')

    "#{clean_name}#{ext}"
  end
end
