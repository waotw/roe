class MediaController < ApplicationController
  skip_before_action :require_authentication
  def show
    file_path = Rails.root.join('site', 'media', params[:path])
    unless File.exist?(file_path)
      file_path = Rails.root.join('site', 'documentation', 'media', params[:path])  # Add 'media' here
    end
    if File.exist?(file_path)
      send_file file_path, disposition: 'inline'
    else
      head :not_found
    end
  end
end
