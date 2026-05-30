class StaticSiteMiddleware
  # Paths that must always hit Rails even in static mode (admin, internal
  # APIs, Rails internals). Everything else under these prefixes won't be
  # served from static_site/.
  RAILS_ONLY_PREFIXES = %w[/admin /system /rails /webhooks /api].freeze

  # Asset prefixes that should be served from static_site/ verbatim
  # (no .html appending, return as-is with a guessed Content-Type).
  ASSET_PREFIXES = %w[/theme/ /media/ /system/ /assets/].freeze

  MIME_TYPES = {
    ".html" => "text/html; charset=utf-8",
    ".css"  => "text/css; charset=utf-8",
    ".js"   => "application/javascript; charset=utf-8",
    ".json" => "application/json; charset=utf-8",
    ".xml"  => "application/xml; charset=utf-8",
    ".txt"  => "text/plain; charset=utf-8",
    ".svg"  => "image/svg+xml",
    ".png"  => "image/png",
    ".jpg"  => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".gif"  => "image/gif",
    ".webp" => "image/webp",
    ".ico"  => "image/x-icon",
    ".woff" => "font/woff",
    ".woff2" => "font/woff2",
    ".ttf"  => "font/ttf",
    ".otf"  => "font/otf",
    ".mp3"  => "audio/mpeg",
    ".mp4"  => "video/mp4",
    ".m4a"  => "audio/mp4",
    ".webm" => "video/webm"
  }.freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)

    if request.get? && !rails_only?(request.path) && static_mode?
      file_path = find_static_file(request.path)
      return serve(file_path) if file_path
    end

    @app.call(env)
  end

  private

  def rails_only?(path)
    RAILS_ONLY_PREFIXES.any? { |p| path == p || path.start_with?("#{p}/") }
  end

  def static_mode?
    SiteConfig.current("site")&.static_generation_enabled || false
  rescue
    false
  end

  def static_root
    @static_root ||= Pathname.new(RoeSitePaths::STATIC_SITE_PATH)
  end

  def find_static_file(path)
    # Assets: serve verbatim (no .html appending). Reject path traversal.
    if ASSET_PREFIXES.any? { |p| path.start_with?(p) }
      candidate = safe_join(path)
      return candidate if candidate && File.file?(candidate)
      return nil
    end

    # Root → index.html
    if path == "/" || path.empty?
      candidate = static_root.join("index.html")
      return candidate.to_s if candidate.exist?
      return nil
    end

    clean = path.sub(%r{\A/}, "").sub(%r{/\z}, "")

    # Exact file (e.g. /sitemap.xml, /robots.txt)
    if File.extname(clean).present?
      candidate = safe_join("/#{clean}")
      return candidate if candidate && File.file?(candidate)
    end

    # /foo → /foo.html
    candidate = safe_join("/#{clean}.html")
    return candidate if candidate && File.file?(candidate)

    # /foo → /foo/index.html
    candidate = safe_join("/#{clean}/index.html")
    return candidate if candidate && File.file?(candidate)

    nil
  end

  # Join a request path onto static_root and confirm the result is still
  # under static_root (defense against `/../etc/passwd`).
  def safe_join(path)
    joined = static_root.join(path.sub(%r{\A/}, "")).cleanpath
    return nil unless joined.to_s.start_with?(static_root.realpath.to_s)
    joined.to_s
  rescue
    nil
  end

  def serve(file_path)
    content_type = MIME_TYPES[File.extname(file_path).downcase] || "application/octet-stream"
    [
      200,
      {
        "Content-Type" => content_type,
        "Content-Length" => File.size(file_path).to_s,
        "Cache-Control" => "public, max-age=3600"
      },
      [ File.binread(file_path) ]
    ]
  end
end

Rails.application.config.middleware.use StaticSiteMiddleware
