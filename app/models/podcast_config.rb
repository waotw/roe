class PodcastConfig
  REQUIRED_FIELDS = %w[title description author email category language artwork link].freeze

  # Canonical iTunes-spec field set. Every podcast entry in
  # podcast.yml carries the full list so blank values become visible
  # "fill me in" prompts in the admin editor — missing keys are
  # invisible, present-but-blank ones aren't. PodcastConfigSeeder and
  # the "Enable Podcasts" modal both emit this exact set.
  #
  # Order matters: it's the order fields render in the YAML output
  # and in any all-canonical-fields admin form.
  CANONICAL_FIELDS = %w[
    title
    description
    author
    email
    owner_name
    category
    subcategory
    category_secondary
    subcategory_secondary
    language
    copyright
    explicit
    type
    artwork
    link
  ].freeze

  # Defaults applied when a canonical field has no value from any
  # source (form input, feed extraction, etc.). Anything not listed
  # defaults to "".
  FIELD_DEFAULTS = {
    "language" => "en",
    "type"     => "episodic",
    "explicit" => "false"
  }.freeze

  # Subscribe app/service links, in display order. Each key is a flat
  # podcast.yml field holding the show's URL on that platform (blank =
  # hidden); the value is the human label rendered on the button. Kept
  # separate from CANONICAL_FIELDS (the iTunes-spec set) — these never
  # go into the feed XML. Surfaced in the admin editor via the same
  # auto-backfill pattern as `audience`, so existing shows pick them up.
  SUBSCRIBE_APPS = {
    "apple_podcasts" => "Apple Podcasts",
    "spotify"        => "Spotify",
    "youtube"        => "YouTube",
    "overcast"       => "Overcast",
    "pocket_casts"   => "Pocket Casts",
    "amazon_music"   => "Amazon Music"
  }.freeze

  # All subscribe-related fields (the app URLs + the display toggle).
  SUBSCRIBE_FIELDS = (SUBSCRIBE_APPS.keys + %w[subscribe_display]).freeze

  # Ordered [{ label:, url: }] for every app/service field a podcast has
  # filled in (blank ones dropped). Feed links are added by the template.
  def self.subscribe_links(config)
    return [] unless config

    SUBSCRIBE_APPS.filter_map do |field, label|
      url = config[field].to_s.strip
      { label: label, url: url } if url.present?
    end
  end

  # How the subscribe section renders: "links" (show all inline, the
  # default) or "menu" (collapse behind a single Subscribe button).
  def self.subscribe_display(config)
    value = config&.dig("subscribe_display").to_s.strip
    %w[links menu].include?(value) ? value : "links"
  end

  def self.default_entry
    CANONICAL_FIELDS.each_with_object({}) { |f, h| h[f] = FIELD_DEFAULTS.fetch(f, "") }
  end

  # Get a specific podcast config by key
  def self.get(podcast_key)
    config = all_podcasts[podcast_key.to_s]
    return nil unless config

    # If this is a series with a parent, merge parent config
    if config["parent"]
      parent_config = all_podcasts[config["parent"]]
      return nil unless parent_config

      # Parent fields + series overrides
      parent_config.merge(config).except("parent")
    else
      config
    end
  end

  # Get all podcast configs (raw)
  # No class-level memoization — rely on SiteConfig's own cache which
  # gets busted when the file changes via content sync
  def self.all_podcasts
    site_config = SiteConfig.current("features/podcast")
    site_config&.config || {}
  end

  # Clear cache
  def self.reload!
    SiteConfig.reload!("features/podcast")
  end

  # Get list of podcast keys for dropdown
  def self.podcast_keys
    all_podcasts.keys.reject { |key| all_podcasts[key]["parent"].present? }
  end

  # Validate a podcast config
  def self.valid?(podcast_key)
    config = get(podcast_key)
    return false unless config

    REQUIRED_FIELDS.all? { |field| config[field].present? }
  end

  # Get feed URL for a podcast
  def self.feed_url(podcast_key)
    config = get(podcast_key)
    return nil unless config

    if podcast_key == podcast_keys.first
      "/podcast/feed.rss"
    else
      "/podcast/#{podcast_key}/feed.rss"
    end
  end
end
