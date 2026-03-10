class MediaController < ApplicationController
  skip_before_action :require_authentication

  def show
    Rails.logger.info "=== MEDIA DEBUG ==="
    Rails.logger.info "Requested path: #{params[:path]}"

    file_path = Rails.root.join('content', 'media', params[:path])
    Rails.logger.info "Trying media: #{file_path} - exists? #{File.exist?(file_path)}"

    unless File.exist?(file_path)
      file_path = Rails.root.join('content', 'documentation', 'media', params[:path])  # Add 'media' here
      Rails.logger.info "Trying docs: #{file_path} - exists? #{File.exist?(file_path)}"
    end

    if File.exist?(file_path)
      send_file file_path, disposition: 'inline'
    else
      Rails.logger.error "NOT FOUND: #{file_path}"
      head :not_found
    end
  end
end
