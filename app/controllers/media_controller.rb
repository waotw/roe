class MediaController < ApplicationController
  skip_before_action :require_authentication

  def show
    file_path = File.join(RoeSitePaths::SITE_PATH, "media", params[:path])
    unless File.exist?(file_path)
      file_path = File.join(RoeSitePaths::SITE_PATH, "documentation", "media", params[:path])
    end
    unless File.exist?(file_path)
      doc_media_paths = Dir.glob(File.join(RoeSitePaths::SITE_PATH, "documentation", "*", "media", params[:path]))
      file_path = doc_media_paths.first if doc_media_paths.any?
    end

    unless File.exist?(file_path)
      head :not_found
      return
    end

    file_size = File.size(file_path)
    mime_type = Mime::Type.lookup_by_extension(File.extname(file_path).delete_prefix(".")).to_s
    mime_type = "application/octet-stream" if mime_type.blank?

    range_header = request.headers["HTTP_RANGE"] || request.headers["Range"]

    if range_header
      # Parse Range header: "bytes=start-end"
      range = parse_range(range_header, file_size)

      if range.nil?
        response.headers["Content-Range"] = "bytes */#{file_size}"
        head :range_not_satisfiable
        return
      end

      first, last = range
      length = last - first + 1

      response.status = 206
      response.headers["Content-Range"]  = "bytes #{first}-#{last}/#{file_size}"
      response.headers["Content-Length"] = length.to_s
      response.headers["Accept-Ranges"]  = "bytes"
      response.headers["Content-Type"]   = mime_type

      File.open(file_path, "rb") do |file|
        file.seek(first)
        self.response_body = file.read(length)
      end
    else
      response.headers["Accept-Ranges"]  = "bytes"
      response.headers["Content-Length"] = file_size.to_s
      response.headers["Content-Type"]   = mime_type

      send_file file_path, disposition: "inline", type: mime_type
    end
  end

  private

  def parse_range(range_header, file_size)
    # Expects format: "bytes=start-end" or "bytes=start-"
    match = range_header.match(/bytes=(\d*)-(\d*)/)
    return nil unless match

    first = match[1].present? ? match[1].to_i : 0
    last  = match[2].present? ? match[2].to_i : file_size - 1

    # Clamp to file bounds
    last = file_size - 1 if last >= file_size

    return nil if first > last || first >= file_size

    [ first, last ]
  end
end
