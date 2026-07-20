class MediaController < ApplicationController
  skip_before_action :require_authentication

  def show
    file_path = resolve_media_path(params[:path].to_s)

    unless file_path
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

  # Resolve a requested media path to a real file, but ONLY within the
  # allowed media roots. /media/*path is a public wildcard route, so
  # params[:path] is attacker-controllable and can contain "../" or glob
  # metacharacters. We expand each candidate and confirm it stays inside its
  # root before returning it (defeats path traversal), and we build the
  # per-scope documentation paths with File.join rather than Dir.glob
  # (defeats glob injection). Returns nil when nothing safe matches.
  def resolve_media_path(rel)
    media_roots.each do |root|
      candidate = File.expand_path(File.join(root, rel))
      return candidate if within?(root, candidate) && File.file?(candidate)
    end
    nil
  end

  # The directories media may be served from: /site/media,
  # /site/documentation/media, and each /site/documentation/<scope>/media.
  # Scope directories are read from disk (no user input), so enumerating
  # them can't be steered by the request.
  def media_roots
    site = RoeSitePaths::SITE_PATH
    roots = [
      File.join(site, "media"),
      File.join(site, "documentation", "media")
    ]

    docs = File.join(site, "documentation")
    if Dir.exist?(docs)
      Dir.children(docs).each do |scope|
        scope_media = File.join(docs, scope, "media")
        roots << scope_media if Dir.exist?(scope_media)
      end
    end

    roots
  end

  # True only when `path` is `root` itself or sits below it — so a "../"
  # that climbs out is rejected. Roots are "/"-suffixed before the prefix
  # check so a sibling like "/site/media-x" can't pass as "/site/media".
  def within?(root, path)
    root = File.expand_path(root)
    path == root || path.start_with?(root + File::SEPARATOR)
  end

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
