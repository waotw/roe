class System::ThemesController < ApplicationController
  include FileValidators

  skip_before_action :require_authentication
  skip_before_action :verify_authenticity_token

  def show
    # Harden this unauthenticated route against path traversal: strip any
    # path components from the filename and constrain the extension to the
    # two we serve, so neither param can escape the theme directories.
    # (The route segment already excludes "/" and "."; this is
    # defense-in-depth.)
    filename = File.basename(params[:filename].to_s)
    format = params[:format] == "js" ? "js" : "css"

    # Build full filename with extension
    full_filename = "#{filename}.#{format}"

    # Determine MIME type
    content_type = format == "js" ? "application/javascript" : "text/css"

    # Check user's installed themes first
    user_file_path = File.join(RoeSitePaths::SITE_PATH, "theme", full_filename)

    # Fall back to app themes if not installed
    app_file_path = Rails.root.join("app", "themes", full_filename)

    file_path = if File.exist?(user_file_path)
      user_file_path
    elsif File.exist?(app_file_path)
      app_file_path
    else
      head :not_found
      return
    end

    return if file_fresh?(file_path)

    send_file file_path, type: content_type, disposition: "inline"
  end

  private

  def detect_extension(filename)
    # If no extension, check what exists
    if File.exist?(File.join(RoeSitePaths::SITE_PATH, "theme", "#{filename}.css"))
      ".css"
    elsif File.exist?(File.join(RoeSitePaths::SITE_PATH, "theme", "#{filename}.js"))
      ".js"
    else
      ".css" # Default fallback
    end
  end

  def mime_type_for(extension)
    case extension
    when ".css"
      "text/css"
    when ".js"
      "application/javascript"
    else
      "text/plain"
    end
  end
end
