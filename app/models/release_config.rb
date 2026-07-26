# Music metadata, read from site/system/features/music.yml. The file's presence
# enables the Music feature (like the other features/*.yml). It is a distribution
# manifest — the one place Roe looks when it renders a player or distributes a
# release — not a home for content. Shape:
#
#   audience: free            # global default (only relevant if members is on)
#   artist: "Waveform Archive" # the default artist — usually just "you"
#   releases:
#     summer-album:
#       title: "Summer Album"
#       cover: /media/images/summer.jpg
#       audience: paid         # overrides the global for this release
#   artists:                   # optional — only for multi-artist sites
#     guest-band: { name: "Guest Band", links: { bandcamp: "https://…" } }
#
# A `post_type: music` post associates via `release: <key>` and inherits down the
# chain (most specific wins): a track's own value → its release → the global.
# Artist bottoms out at the site author (site.yml). Resolution is read-time — the
# post stores only its differences.
#
# An absent file means the feature is off — never an error.
class ReleaseConfig
  FILE = SiteConfig::FEATURES_PATH.join("music.yml")

  def self.enabled?
    File.exist?(FILE)
  end

  def self.config
    c = SiteConfig.current("features/music")&.config
    c.is_a?(Hash) ? c : {}
  end

  # The releases map (top-level `releases:`).
  def self.all_releases
    r = config["releases"]
    r.is_a?(Hash) ? r : {}
  end

  # The optional artists map (top-level `artists:`), for multi-artist sites.
  def self.all_artists
    a = config["artists"]
    a.is_a?(Hash) ? a : {}
  end

  def self.release_keys
    all_releases.keys
  end

  def self.get(key)
    return nil if key.blank?
    all_releases[key.to_s]
  end

  def self.exists?(key)
    get(key).present?
  end

  # The global default audience (only meaningful when members is enabled).
  def self.global_audience
    config["audience"].to_s.strip.downcase.presence
  end

  # The global default artist.
  def self.global_artist
    config["artist"].to_s.strip.presence
  end

  # Resolve a release's audience: release override → global default → "free".
  def self.audience_for(key)
    get(key).to_h["audience"].to_s.strip.downcase.presence || global_audience || "free"
  end

  # A release is paid when its resolved audience is "paid".
  def self.paid?(key)
    audience_for(key) == "paid"
  end

  # Resolve a release's artist: release override → global default → site author.
  # (A track can still override this on its own metadata, resolved by the caller.)
  def self.artist_for(key)
    get(key).to_h["artist"].to_s.strip.presence ||
      global_artist ||
      SiteConfig.get("author_name").presence ||
      SiteConfig.get("author").presence
  end

  def self.reload!
    SiteConfig.reload!("features/music")
  end
end
