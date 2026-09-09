require "net/http"
require "uri"

# Downloads one external media URL into /site/media/<bucket> and returns its
# local "/media/<bucket>/<file>" path (nil on failure — the caller leaves the
# reference untouched). Handles redirects and long timeouts for large audio /
# video; dedupes identical bytes.
class MediaImporter::Fetcher
  MAX_REDIRECTS = 5
  OPEN_TIMEOUT  = 15
  READ_TIMEOUT  = 300
  USER_AGENT    = "Roe-CMS/1.0 (Media Importer)"

  CONTENT_TYPE_EXT = {
    "image/jpeg" => ".jpg", "image/png" => ".png", "image/gif" => ".gif",
    "image/webp" => ".webp", "image/svg+xml" => ".svg", "image/avif" => ".avif",
    "audio/mpeg" => ".mp3", "audio/mp4" => ".m4a", "audio/x-m4a" => ".m4a",
    "audio/aac" => ".aac", "audio/wav" => ".wav", "audio/ogg" => ".ogg",
    "video/mp4" => ".mp4", "video/quicktime" => ".mov", "video/webm" => ".webm"
  }.freeze

  def initialize(media_root: File.join(RoeSitePaths::SITE_PATH, "media"))
    @media_root = media_root
  end

  def fetch(url, type)
    body, content_type = download(url)
    return nil if body.nil? || body.empty?

    dir = File.join(@media_root, type.to_s)
    FileUtils.mkdir_p(dir)
    filename = destination_name(dir, url, extension_for(url, content_type), body)
    File.binwrite(File.join(dir, filename), body)
    "/media/#{type}/#{filename}"
  rescue => e
    Rails.logger.warn "[MediaImporter] fetch failed #{url}: #{e.class} #{e.message}"
    nil
  end

  private

  def download(url, redirects_left: MAX_REDIRECTS)
    uri = URI.parse(url)
    raise "unsupported scheme" unless %w[http https].include?(uri.scheme)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = USER_AGENT
    response = http.request(request)

    case response
    when Net::HTTPSuccess
      [ response.body, response["content-type"] ]
    when Net::HTTPRedirection
      raise "too many redirects" if redirects_left <= 0
      location = response["location"]
      location = URI.join(url, location).to_s unless location.to_s.start_with?("http")
      download(location, redirects_left: redirects_left - 1)
    else
      raise "HTTP #{response.code} #{response.message}"
    end
  end

  def extension_for(url, content_type)
    ext = File.extname(url.to_s.split(/[?#]/).first.to_s).downcase
    return ext if ext.match?(/\A\.\w{2,5}\z/)
    CONTENT_TYPE_EXT[content_type.to_s.split(";").first&.strip&.downcase] || ".bin"
  end

  # Preserve the source basename; reuse on identical bytes, else -2, -3, …
  def destination_name(dir, url, ext, body)
    base = sanitize(File.basename(url.to_s.split(/[?#]/).first.to_s, ".*"))
    base = "media" if base.empty?
    name = "#{base}#{ext}"
    return name if free_or_same?(File.join(dir, name), body)

    n = 2
    loop do
      candidate = "#{base}-#{n}#{ext}"
      return candidate if free_or_same?(File.join(dir, candidate), body)
      n += 1
    end
  end

  def free_or_same?(path, body)
    !File.exist?(path) || File.binread(path) == body
  end

  def sanitize(name)
    name.gsub(/[^\w.\-]+/, "-").sub(/\A-+/, "").presence || ""
  end
end
