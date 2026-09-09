# Turns a music release into the config hash FeedGenerator's :podcast format
# expects, so a release can be submitted to Apple Podcasts, Spotify or any
# podcatcher without going near the Podcast feature. Nothing here reads or
# writes podcast.yml — a release feed and a show are separate things that
# happen to share a file format.
#
# Almost every field is derived. The two Apple requires that a release has no
# natural answer for:
#
#   category — Apple validates against a fixed list, so a release's free-text
#              `genre` can't fill it. For music the answer is always "Music";
#              the genre still travels, as a plain RSS <category> (see below).
#   email    — used by Apple to verify feed ownership. Comes from site.yml,
#              the same place podcast.yml seeds its own from.
class ReleaseFeed
  # Apple's fixed category list has exactly one right answer for a release.
  ITUNES_CATEGORY = "Music"

  # Serial, not episodic: clients then play oldest-first, which for a release
  # is the running order. Episodic would put the last track first.
  ITUNES_TYPE = "serial"

  attr_reader :key

  def initialize(key)
    @key = key.to_s
  end

  def release
    @release ||= ReleaseConfig.get(key).to_h
  end

  def exists?  = release.present?
  def enabled? = ReleaseConfig.feed_enabled?(key)

  # No public feed when the release has nothing public in it. A paid release
  # with a free single still gets one, carrying that single — the same sampler
  # model a podcast uses. Resolved per track, so a track that opts out of a
  # paid release counts.
  def paid?
    return false if SiteConfig.feature("members", "everyone.show_paid_content")

    tracks.none? { |t| t.audience != "paid" }
  end

  # Published tracks on this release, in running order. Tracks without a
  # number sort last rather than jumping to the front on a nil compare.
  def tracks
    Post
      .published
      .where("json_extract(metadata, '$.post_type') = ?", "music")
      .where("json_extract(metadata, '$.release') = ?", key)
      .to_a
      .sort_by { |p| [ p.metadata["track_number"].presence&.to_i || Float::INFINITY, p.title.to_s ] }
  end

  # The FeedGenerator :podcast config. `medium` and `genre` are read only by
  # the music branch of the generator; a podcast config never sets them.
  def feed_config
    {
      "title"       => release["title"].presence || key,
      "description" => release["synopsis"].to_s,
      "author"      => ReleaseConfig.artist_for(key).to_s,
      "owner_name"  => ReleaseConfig.artist_for(key).to_s,
      "email"       => owner_email,
      "artwork"     => release["cover"].to_s,
      "link"        => link,
      "language"    => language,
      "copyright"   => release["copyright"].presence || default_copyright,
      "category"    => ITUNES_CATEGORY,
      "type"        => ITUNES_TYPE,
      "explicit"    => explicit?,
      "medium"      => "music",
      "genre"       => release["genre"].to_s
    }
  end

  # Apple verifies ownership by emailing this address, so a feed without one
  # can be published but not submitted. Surfaced in the admin rather than
  # failing here.
  def owner_email
    SiteConfig.get("author_email").to_s
  end

  def link
    base = SiteConfig.site_url.to_s.chomp("/")
    base.present? ? "#{base}/music/#{key}" : ""
  end

  def language
    SiteConfig.get("language").presence || "en"
  end

  # A release is explicit when any track on it is. Apple asks at the channel
  # level, and one flagged track makes the whole release flagged.
  def explicit?
    tracks.any? { |t| ReleaseConfig.truthy?(t.metadata["explicit"]) }
  end

  def default_copyright
    artist = ReleaseConfig.artist_for(key).to_s
    year = release["release_date"].to_s[/\A(\d{4})/, 1] || Time.now.year.to_s
    artist.present? ? "℗ & © #{year} #{artist}" : ""
  end
end
