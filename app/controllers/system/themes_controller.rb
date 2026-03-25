class System::ThemesController < ApplicationController
  skip_before_action :require_authentication

  def show
    filename = params[:filename]
    filename = "#{filename}.css" unless filename.end_with?('.css')
    file_path = Rails.root.join('site', 'theme', filename)

    if File.exist?(file_path)
      expires_in 1.year, public: true
      send_file file_path,
        type: 'text/css',
        disposition: 'inline'
    else
      head :not_found
    end
  end
end
