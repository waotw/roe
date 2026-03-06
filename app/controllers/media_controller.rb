class MediaController < ApplicationController
  skip_before_action :require_authentication # or whatever your auth is called

  def show
    file_path = Rails.root.join('content', 'media', params[:path])

    if File.exist?(file_path)
      send_file file_path, disposition: 'inline'
    else
      head :not_found
    end
  end
end
