class System::ThemesController < ApplicationController
  skip_before_action :require_authentication
  skip_before_action :verify_authenticity_token

  def show
    filename = params[:filename]
    format = params[:format] || 'css'

    # Build full filename with extension
    full_filename = "#{filename}.#{format}"

    # Determine MIME type
    content_type = format == 'js' ? 'application/javascript' : 'text/css'

    # Check user's installed themes first
    user_file_path = File.join(RoeSitePaths::SITE_PATH, 'theme', full_filename)

    # Fall back to app themes if not installed
    app_file_path = Rails.root.join('app', 'themes', full_filename)

    file_path = if File.exist?(user_file_path)
      user_file_path
    elsif File.exist?(app_file_path)
      app_file_path
    else
      head :not_found
      return
    end

    # Use file modification time for caching
    last_modified = File.mtime(file_path)

    # Cache headers
    response.headers['Cache-Control'] = 'no-cache, must-revalidate'
    response.headers['Last-Modified'] = last_modified.httpdate
    response.headers['ETag'] = last_modified.to_i.to_s

    # Check if browser's cached version is still valid
    if stale?(last_modified: last_modified, etag: last_modified.to_i)
      send_file file_path, type: content_type, disposition: 'inline'
    end
  end

  private

  def detect_extension(filename)
    # If no extension, check what exists
    if File.exist?(File.join(RoeSitePaths::SITE_PATH, 'theme', "#{filename}.css"))
      '.css'
    elsif File.exist?(File.join(RoeSitePaths::SITE_PATH, 'theme', "#{filename}.js"))
      '.js'
    else
      '.css' # Default fallback
    end
  end

  def mime_type_for(extension)
    case extension
    when '.css'
      'text/css'
    when '.js'
      'application/javascript'
    else
      'text/plain'
    end
  end
end
