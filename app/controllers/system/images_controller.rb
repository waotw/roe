class System::ImagesController < ApplicationController
  skip_before_action :require_authentication

  def show
    image_path = File.join(RoeSitePaths::SITE_PATH, 'system', 'assets', 'images', params[:filename])

    if File.exist?(image_path)
      send_file image_path,
        type: image_mime_type(params[:filename]),
        disposition: 'inline'
    else
      head :not_found
    end
  end

  private

  def image_mime_type(filename)
    case File.extname(filename)
    when '.svg' then 'image/svg+xml'
    when '.png' then 'image/png'
    when '.jpg', '.jpeg' then 'image/jpeg'
    when '.ico' then 'image/x-icon'
    when '.webp' then 'image/webp'
    else 'application/octet-stream'
    end
  end
end
