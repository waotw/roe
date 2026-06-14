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
