require "net/http"
require "uri"

# Fetches a podcast RSS feed by URL and returns the parsed result. Handles
# HTTPS, redirects, and timeouts. Token-bearing URLs (e.g. private Substack
# feeds) flow through unchanged — callers are responsible for not logging
# or persisting the URL itself.
class PodcastFeedFetcher
  TIMEOUT_SECONDS = 30
  MAX_REDIRECTS = 5
  USER_AGENT = "Roe-CMS/1.0 (Podcast Feed Importer)"

  Result = Struct.new(:success?, :data, :error, keyword_init: true)

  def self.fetch(url)
    new(url).fetch
  end

  def initialize(url)
    @url = url.to_s.strip
  end

  def fetch
    return failure("URL is blank") if @url.empty?

    xml = http_get(@url)
    return failure("Empty response body") if xml.to_s.strip.empty?

    parsed = PodcastFeedParser.parse(xml)
    Result.new(success?: true, data: parsed, error: nil)
  rescue => e
    # Don't log @url — it may contain a paywall token. Just the class/message.
    Rails.logger.warn "[PodcastFeedFetcher] #{e.class}: #{e.message}"
    failure("#{e.class}: #{e.message}")
  end

  private

  def failure(msg)
    Result.new(success?: false, data: nil, error: msg)
  end

  def http_get(url, redirects_left: MAX_REDIRECTS)
    uri = URI.parse(url)
    raise "Unsupported scheme: #{uri.scheme}" unless %w[http https].include?(uri.scheme)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.read_timeout = TIMEOUT_SECONDS
    http.open_timeout = TIMEOUT_SECONDS

    request = Net::HTTP::Get.new(uri.request_uri)
    request["User-Agent"] = USER_AGENT
    request["Accept"] = "application/rss+xml, application/xml;q=0.9, */*;q=0.8"

    response = http.request(request)

    case response
    when Net::HTTPSuccess
      response.body
    when Net::HTTPRedirection
      raise "Too many redirects" if redirects_left <= 0
      next_url = response["location"]
      raise "Redirect with no Location header" if next_url.to_s.empty?
      http_get(next_url, redirects_left: redirects_left - 1)
    else
      raise "HTTP #{response.code} #{response.message}"
    end
  end
end
