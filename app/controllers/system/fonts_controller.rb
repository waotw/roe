class System::FontsController < ApplicationController
  skip_before_action :require_authentication

  def show
    filename = params[:filename]
    file_path = File.join(RoeSitePaths::SITE_PATH, "system/assets/fonts", filename)

    if File.exist?(file_path)
      # Set aggressive caching for fonts (they rarely change)
      expires_in 1.year, public: true

      send_file file_path,
        type: font_mime_type(filename),  # Changed from mime_type_for
        disposition: "inline",
        filename: filename
    else
      head :not_found
    end
  end

  private

  def font_mime_type(filename)
    case File.extname(filename)
    when ".woff2" then "font/woff2"
    when ".woff" then "font/woff"
    when ".ttf" then "font/ttf"
    when ".otf" then "font/otf"
    else "application/octet-stream"
    end
  end
end
