class System::JavascriptsController < ApplicationController
  skip_before_action :require_authentication
  skip_before_action :verify_authenticity_token

  def show
    # Serve the site-facing vanilla JS (search.js, gallery.js, checkout.js).
    # SiteJavascript prefers the per-site copy in site/javascript/ and falls
    # back to the shipped app/site_js/; the basename guard blocks traversal.
    filename = File.basename(params[:filename].to_s)
    format = params[:format] == "css" ? "css" : "js"
    full_filename = "#{filename}.#{format}"
    content_type = format == "js" ? "application/javascript" : "text/css"

    file_path = SiteJavascript.path(full_filename)

    unless File.exist?(file_path)
      head :not_found
      return
    end

    last_modified = File.mtime(file_path)
    response.headers["Cache-Control"] = "no-cache, must-revalidate"
    response.headers["Last-Modified"] = last_modified.httpdate
    response.headers["ETag"] = last_modified.to_i.to_s

    if stale?(last_modified: last_modified, etag: last_modified.to_i)
      send_file file_path, type: content_type, disposition: "inline"
    end
  end
end
