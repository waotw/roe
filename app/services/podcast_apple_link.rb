require "json"
require "net/http"
require "uri"

# Helpers for Apple Podcasts links. An Apple URL like
#   https://podcasts.apple.com/us/podcast/the-briefcase-podcast/id553753672
# carries the show's numeric iTunes ID (553753672). The free iTunes Lookup
# API resolves that ID to the show's real RSS feed, and the same ID yields
# canonical Apple Podcasts + Overcast subscribe URLs.
module PodcastAppleLink
  module_function

  APPLE_URL  = /podcasts\.apple\.com/i
  ID_RE      = /id(\d+)/
  LOOKUP_URL = "https://itunes.apple.com/lookup".freeze

  def apple_url?(url)
    url.to_s.match?(APPLE_URL)
  end

  # Numeric podcast ID from an Apple Podcasts URL, or nil for anything else.
  def podcast_id(url)
    return nil unless apple_url?(url)
    url.to_s[ID_RE, 1]
  end

  # Resolve an Apple podcast ID via the iTunes Lookup API. Returns a hash with
  # :feed_url and :artwork_url — the feed usually carries its own art, but some
  # feeds omit <itunes:image>, and Apple's copy is a good fallback. Empty hash
  # on any failure. `fetcher` is injectable for tests — a callable taking a URL
  # and returning the response body.
  def lookup(podcast_id, fetcher: method(:http_get))
    return {} if podcast_id.to_s.empty?
    result = JSON.parse(fetcher.call("#{LOOKUP_URL}?id=#{podcast_id}&entity=podcast").to_s).dig("results", 0) || {}
    {
      feed_url:    result["feedUrl"].to_s.presence,
      artwork_url: (result["artworkUrl600"] || result["artworkUrl100"] || result["artworkUrl60"]).to_s.presence
    }
  rescue => e
    Rails.logger.warn "[PodcastAppleLink] lookup failed (#{e.class}: #{e.message})"
    {}
  end

  # Just the RSS feed URL for an Apple podcast ID (or nil).
  def feed_url(podcast_id, fetcher: method(:http_get))
    lookup(podcast_id, fetcher: fetcher)[:feed_url]
  end

  # Canonical subscribe URLs derivable from an Apple ID.
  def subscribe_links(podcast_id)
    return {} if podcast_id.to_s.empty?
    {
      "apple_podcasts" => "https://podcasts.apple.com/podcast/id#{podcast_id}",
      "overcast"       => "https://overcast.fm/itunes#{podcast_id}"
    }
  end

  # Plain HTTPS GET for the public lookup API (no tokens involved).
  def http_get(url)
    uri  = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = 15
    http.read_timeout = 15
    req = Net::HTTP::Get.new(uri.request_uri)
    req["User-Agent"] = "Roe-CMS/1.0 (Podcast Feed Importer)"
    http.request(req).body
  end
end
