# frozen_string_literal: true

require "cgi"
require "net/http"
require "uri"

# A video hosted somewhere else, given by the link you'd copy from that
# site's Share button. Roe recognises the link wherever it takes a video —
# a video post's `video:` field, `![title](link)` in Markdown, the player
# card — and plays it in the host's own player instead of a <video> tag.
#
#   VideoEmbed.for("https://youtu.be/dQw4w9WgXcQ?si=abc&t=42")
#   # => #<VideoEmbed provider=:youtube id="dQw4w9WgXcQ" start=42>
#   VideoEmbed.for("/media/video/clip.mp4")  # => nil — a file of ours
#
# YouTube only, for now. Another service is one more entry in PROVIDERS:
# a pattern that finds the video's id in its links, and how to build the
# player and thumbnail addresses from that id.
class VideoEmbed
  # YouTube ids are 11 characters from this set.
  YOUTUBE_ID = /[A-Za-z0-9_-]{11}/

  PROVIDERS = {
    youtube: {
      name: "YouTube",
      hosts: %w[youtube.com www.youtube.com m.youtube.com music.youtube.com
                youtu.be www.youtu.be youtube-nocookie.com www.youtube-nocookie.com],
      # Path forms, after the host. watch?v= is read from the query below.
      paths: [
        %r{\A/(#{YOUTUBE_ID})\z},                                   # youtu.be/ID
        %r{\A/(?:embed|shorts|live|v|e)/(#{YOUTUBE_ID})(?:/|\z)}    # /embed/ID, /shorts/ID …
      ],
      query_id: "v",
      id: /\A#{YOUTUBE_ID}\z/
    }
  }.freeze

  attr_reader :provider, :id, :start, :url

  # nil unless `src` is a link to a video on a known service.
  def self.for(src)
    url = CGI.unescapeHTML(src.to_s.strip)
    return nil unless url.match?(%r{\Ahttps?://}i)

    uri = URI.parse(url)
    host = uri.host.to_s.downcase
    provider, config = PROVIDERS.find { |_, c| c[:hosts].include?(host) }
    return nil unless provider

    id = config[:paths].lazy.filter_map { |re| uri.path.to_s[re, 1] }.first
    query = URI.decode_www_form(uri.query.to_s).to_h
    id ||= query[config[:query_id]] if config[:query_id] && query[config[:query_id]].to_s.match?(config[:id])
    return nil unless id

    new(provider: provider, id: id, start: parse_start(query["t"] || query["start"]), url: url,
        vertical: uri.path.to_s.start_with?("/shorts/"))
  rescue URI::InvalidURIError, ArgumentError
    nil
  end

  def self.embed?(src) = !self.for(src).nil?

  # "42", "42s", "1m30s", "1h2m3s" → seconds. YouTube's share sheet writes
  # the first; links copied from the address bar can carry the others.
  def self.parse_start(value)
    str = value.to_s.strip
    return nil if str.empty?
    return str.to_i if str.match?(/\A\d+\z/)

    parts = str.match(/\A(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?\z/)
    return nil unless parts && parts[0].present?

    parts[1].to_i * 3600 + parts[2].to_i * 60 + parts[3].to_i
  end

  def initialize(provider:, id:, start: nil, url: nil, vertical: false)
    @provider = provider
    @id = id
    @start = start.to_i.positive? ? start.to_i : nil
    @url = url
    @vertical = vertical
  end

  def provider_name = PROVIDERS.dig(provider, :name)

  # Shorts are portrait; everything else plays 16:9.
  def vertical? = @vertical

  # youtube-nocookie.com: YouTube's own privacy-enhanced player. It sets no
  # tracking cookies until the visitor presses play.
  def player_url
    params = { "rel" => "0" }
    params["start"] = start if start
    "https://www.youtube-nocookie.com/embed/#{id}?#{URI.encode_www_form(params)}"
  end

  # Where the video lives on YouTube — what email and feeds link to.
  def watch_url
    "https://www.youtube.com/watch?#{URI.encode_www_form({ "v" => id, "t" => start }.compact)}"
  end

  # hqdefault exists for every video; the sharper maxresdefault doesn't.
  def thumbnail_url = "https://i.ytimg.com/vi/#{id}/hqdefault.jpg"

  # The video's length in whole seconds, or nil when it can't be found (a
  # live stream, a private video, YouTube unreachable). Remembered for a
  # week once found; a failure isn't, so the next try asks again.
  #
  # YouTube's oEmbed answer has no length, and its player API only works on
  # a page the video's owner allows embedding from. The video's own page
  # does carry it — `"lengthSeconds":"213"` in the data the page loads with
  # — so that's read, the way a browser would see it.
  def duration_seconds
    key = "video_embed:duration:#{provider}:#{id}"
    cached = Rails.cache.read(key)
    return cached if cached

    seconds = self.class.length_from_page(fetch_watch_page)
    Rails.cache.write(key, seconds, expires_in: 7.days) if seconds
    seconds
  end

  # The first "lengthSeconds" on the page is the video's own (later ones
  # belong to suggested videos). Zero means a live stream: no length yet.
  def self.length_from_page(html)
    seconds = html.to_s[/"lengthSeconds":"(\d+)"/, 1].to_i
    seconds.positive? ? seconds : nil
  end

  # The player, for web pages. `label` names it for screen readers — the
  # post's title, or the alt text of a Markdown embed.
  #
  # width/height plus aspect-ratio give the frame its shape before it loads,
  # and width:100% lets it fill the column. Set inline so it works on every
  # site straight away, themes included, without a theme update.
  # referrerpolicy: YouTube refuses to play embeds that send no referrer.
  def iframe_html(label: nil, extra_class: nil)
    title = label.presence || "#{provider_name} video"
    ratio, width, height, max = vertical? ? [ "9/16", 315, 560, "max-width:360px;" ] : [ "16/9", 560, 315, "" ]
    classes = [ "video-external", "video-external-#{provider}", ("is-vertical" if vertical?), extra_class ].compact.join(" ")

    <<~HTML.squish.html_safe
      <div class="#{h(classes)}" data-video-url="#{h(url || watch_url)}" data-video-title="#{h(label)}">
        <iframe src="#{h(player_url)}" title="#{h(title)}" width="#{width}" height="#{height}"
                style="display:block;width:100%;#{max}height:auto;aspect-ratio:#{ratio};border:0"
                loading="lazy" referrerpolicy="strict-origin-when-cross-origin"
                allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
                allowfullscreen></iframe>
      </div>
    HTML
  end

  # A thumbnail linking to the video, for places an iframe can't go: email
  # clients strip them, and feed readers often do. A <div>, like the player,
  # so the Markdown pipeline unwraps it from kramdown's <p> the same way.
  def link_html(label: nil)
    title = label.presence || "Watch on #{provider_name}"
    <<~HTML.squish.html_safe
      <div class="video-external-link"><a href="#{h(watch_url)}"><img src="#{h(thumbnail_url)}"
        alt="#{h(title)}" width="480" height="360" style="display:block;max-width:100%;height:auto"></a>
        <p><a href="#{h(watch_url)}">▶ #{h(title)}</a></p></div>
    HTML
  end

  private

  WATCH_PAGE_HEADERS = {
    "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
                    "(KHTML, like Gecko) Chrome/130.0 Safari/537.36",
    "Accept-Language" => "en",
    # Skips the EU cookie-consent page, which would otherwise come back
    # instead of the video's page and has no length on it.
    "Cookie" => "CONSENT=YES+1; SOCS=CAI"
  }.freeze

  # The video's YouTube page, or nil. Follows a couple of redirects and
  # gives up quickly: this runs while someone waits in the editor.
  def fetch_watch_page(url = "https://www.youtube.com/watch?v=#{id}", redirects: 3)
    uri = URI.parse(url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                               open_timeout: 5, read_timeout: 8) do |http|
      http.get(uri.request_uri, WATCH_PAGE_HEADERS)
    end

    case response
    when Net::HTTPSuccess then response.body
    when Net::HTTPRedirection
      fetch_watch_page(URI.join(url, response["location"]).to_s, redirects: redirects - 1) if redirects.positive?
    end
  rescue StandardError => e
    Rails.logger.warn "[VideoEmbed] #{provider} #{id}: couldn't read the video's page (#{e.class}: #{e.message})"
    nil
  end

  def h(value) = ERB::Util.html_escape(value.to_s)
end
