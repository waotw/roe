class System::FontsController < ApplicationController
  skip_before_action :require_authentication

  def show
    font_path = Rails.root.join('content', 'system', 'assets', 'fonts', params[:filename])

    if File.exist?(font_path)
      send_file font_path,
        type: font_mime_type(params[:filename]),
        disposition: 'inline'
    else
      head :not_found
    end
  end

  private

  def font_mime_type(filename)
    case File.extname(filename)
    when '.woff2' then 'font/woff2'
    when '.woff' then 'font/woff'
    when '.ttf' then 'font/ttf'
    when '.otf' then 'font/otf'
    else 'application/octet-stream'
    end
  end
end
