class System::ThemesController < ApplicationController
  skip_before_action :require_authentication

  def show
      filename = params[:filename]
      filename = "#{filename}.css" unless filename.end_with?('.css')

      # Check user's installed themes first
      user_file_path = Rails.root.join('site', 'theme', filename)

      # Fall back to app themes if not installed
      app_file_path = Rails.root.join('app', 'themes', filename)

      file_path = if File.exist?(user_file_path)
        user_file_path
      elsif File.exist?(app_file_path)
        app_file_path
      else
        nil
      end

      if file_path
        # Use file modification time for caching
        last_modified = File.mtime(file_path)

        # Force browser to revalidate (but still use cache if file unchanged)
        response.headers['X-Served-By'] = 'ThemesController'
        response.headers['Cache-Control'] = 'no-cache, must-revalidate'
        response.headers['Last-Modified'] = last_modified.httpdate
        response.headers['ETag'] = last_modified.to_i.to_s

        # Check if browser's cached version is still valid
        if stale?(last_modified: last_modified, etag: last_modified.to_i)
          send_file file_path, type: 'text/css', disposition: 'inline'
        end
      else
        head :not_found
      end
    end
end
