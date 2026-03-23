class Admin::SystemAssetsController < ApplicationController
  layout "application"

  ASSETS_PATH = Rails.root.join('site/system/assets')
  FONTS_PATH = ASSETS_PATH.join('fonts')

  def index
    # Main index if we want it later
  end

  def browse_fonts
    # Ensure fonts directory exists
    FileUtils.mkdir_p(FONTS_PATH)

    @fonts = Dir.glob(FONTS_PATH.join('*')).map do |file_path|
      {
        filename: File.basename(file_path),
        path: file_path,
        size: File.size(file_path),
        modified: File.mtime(file_path)
      }
    end.sort_by { |f| f[:filename] }
  end

  def browse_images
    images_path = ASSETS_PATH.join('images')
    # Ensure images directory exists
    FileUtils.mkdir_p(images_path)

    @images = Dir.glob(images_path.join('*')).map do |file_path|
      {
        filename: File.basename(file_path),
        path: file_path,
        size: File.size(file_path),
        modified: File.mtime(file_path)
      }
    end.sort_by { |f| f[:filename] }
  end

  def create
    uploaded_file = params[:file]
    asset_type = params[:asset_type] || 'fonts'

    folder_path = ASSETS_PATH.join(asset_type)
    FileUtils.mkdir_p(folder_path)

    # Sanitize filename
    filename = sanitize_filename(uploaded_file.original_filename)

    # Check for duplicates and append counter if needed
    base_name = File.basename(filename, File.extname(filename))
    extension = File.extname(filename)
    counter = 1
    final_filename = filename

    while File.exist?(folder_path.join(final_filename))
      final_filename = "#{base_name}-#{counter}#{extension}"
      counter += 1
    end

    file_path = folder_path.join(final_filename)

    # Save file
    File.open(file_path, 'wb') do |file|
      file.write(uploaded_file.read)
    end

    respond_to do |format|
      format.json { render json: { success: true, filename: final_filename } }
      format.html { redirect_to browse_fonts_admin_system_assets_path, notice: "Font uploaded: #{final_filename}" }
    end
  rescue => e
    respond_to do |format|
      format.json { render json: { success: false, error: e.message }, status: :unprocessable_entity }
      format.html { redirect_to browse_fonts_admin_system_assets_path, alert: "Upload failed: #{e.message}" }
    end
  end

  def destroy
    filename = params[:id]
    asset_type = params[:asset_type] || 'fonts'
    file_path = ASSETS_PATH.join(asset_type, filename)

    Rails.logger.info "Attempting to delete: #{file_path}"
    Rails.logger.info "File exists: #{File.exist?(file_path)}"

    if File.exist?(file_path)
      File.delete(file_path)
      redirect_to browse_fonts_admin_system_assets_path, notice: "#{filename} deleted successfully"
    else
      Rails.logger.error "File not found at: #{file_path}"
      redirect_to browse_fonts_admin_system_assets_path, alert: "File not found: #{file_path}"
    end
  end

  def available_fonts
    fonts = Dir.glob(FONTS_PATH.join('*')).map { |f| File.basename(f) }
    render json: { fonts: fonts }
  end

  private

  def sanitize_filename(filename)
    # Get extension
    ext = File.extname(filename)
    basename = File.basename(filename, ext)

    # Keep original case for fonts, just remove dangerous characters
    clean_name = basename.gsub(/[^a-zA-Z0-9\-_]/, '-').gsub(/-+/, '-')

    "#{clean_name}#{ext}"
  end
end
