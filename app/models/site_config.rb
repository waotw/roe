class SiteConfig < ApplicationRecord
  SYSTEM_PATH = File.join(RoeSitePaths::SITE_PATH, "system")
  SITE_PATH = File.join(SYSTEM_PATH, "global")
  FEATURES_PATH = Pathname.new(File.join(SYSTEM_PATH, "features"))
  DEFAULTS_PATH = Pathname.new(File.join(SYSTEM_PATH, "defaults"))
  INTEGRATIONS_PATH = Pathname.new(File.join(SYSTEM_PATH, "integrations"))

  SITE_FILE = File.join(SITE_PATH, "site.yml")
  FONTS_FILE = File.join(SITE_PATH, "fonts.yml")
  CUSTOM_CODE_FILE = File.join(SITE_PATH, "custom_code.yml")
  DEVELOPMENT_FILE = File.join(SITE_PATH, "development.yml")
  DEPLOY_FILE = File.join(SITE_PATH, "deploy.yml")
  CONTENT_FILE = File.join(SITE_PATH, "content.yml")
  SECURITY_FILE = File.join(SITE_PATH, "security.yml")

  # content.yml keys that used to live flat in site.yml. Lets `content`
  # read a pre-split install (before the boot migration moves them).
  CONTENT_LEGACY_KEYS = {
    "search.all_pages"           => "search_all_pages",
    "search.roe_docs"            => "search_roe_docs",
    "search.results_when_opened" => "results_when_opened",
    "soft_line_breaks"           => "soft_line_breaks"
  }.freeze

  CACHE_KEY_PREFIX = "site_config"

  # A site-level setting, read from site.yml. Supports dotted keys
  # ("theme.active").
  #
  # The one way site config is read. Deliberately NOT through `current` /
  # Rails.cache: the cache store is Solid Cache, which is database-backed, so
  # that path needs a database before it even reaches find_by. Config has to
  # stay readable when the database isn't there — recovery boots, rake tasks,
  # a half-migrated install.
  #
  # Reading the file can't be stale, either. sync_from_file is the only thing
  # that writes a SiteConfig record's config, and it copies from the file, so
  # the file is always at least as fresh as the record.
  def self.get(key)
    file_config&.dig(*key.to_s.split("."))
  end

  # site.yml, parsed once and re-read only when the file actually changes.
  #
  # It used to parse on every call, which is fine for a page render and not
  # fine for ApplicationMailer: its `default from:` is a lambda ActionMailer
  # evaluates per message, so sending a newsletter re-parsed site.yml once per
  # recipient to fetch a value that changes about once a year.
  #
  # Keyed on mtime AND size rather than mtime alone — a filesystem with
  # one-second mtime granularity can't distinguish two writes in the same
  # second, and reload! clears this outright for the cases that matter.
  def self.file_config
    return nil unless File.exist?(SITE_FILE)

    stat  = File.stat(SITE_FILE)
    stamp = [ stat.mtime, stat.size ]
    return @file_config if @file_config_stamp == stamp

    parsed = parse_yaml(SITE_FILE)
    # Stamped only after a successful parse, so a broken file is retried
    # rather than remembered as nil.
    @file_config       = parsed
    @file_config_stamp = stamp
    parsed
  rescue => e
    Rails.logger.error "SiteConfig.get error: #{e.message}"
    nil
  end

  # Parse a config file.
  #
  # Deliberately not YAML.load_file: bootsnap caches that on (mtime, size),
  # and mtime is whole-second on at least some filesystems — so two writes of
  # the same byte length inside one second hand back the FIRST parse. That
  # isn't hypothetical. Saving a config twice in quick succession (a one-
  # character fix, an editor autosave) left the database record holding the
  # previous contents while the file on disk held the new ones, and it stayed
  # that way until the next save landed in a different second.
  #
  # Same parsing defaults as load_file, so nothing else changes.
  def self.parse_yaml(path)
    SiteFile.read_yaml(path)
  end

  def self.reset_file_cache!
    @file_config = nil
    @file_config_stamp = nil
  end

  # Get fonts config
  def self.fonts(key = nil)
    return nil unless File.exist?(FONTS_FILE)
    config_data = parse_yaml(FONTS_FILE)

    return config_data unless key

    keys = key.to_s.split(".")
    config_data&.dig(*keys)
  rescue => e
    Rails.logger.error "SiteConfig.fonts error: #{e.message}"
    nil
  end

  # Get custom code config (head_html, footer_html, themes scoping).
  # Returns nil when the file doesn't exist yet — the layout's
  # renderer treats nil as "nothing to inject", so brand-new installs
  # never error on the missing file.
  def self.custom_code(key = nil)
    return nil unless File.exist?(CUSTOM_CODE_FILE)
    config_data = parse_yaml(CUSTOM_CODE_FILE)

    return config_data unless key

    keys = key.to_s.split(".")
    config_data&.dig(*keys)
  rescue => e
    Rails.logger.error "SiteConfig.custom_code error: #{e.message}"
    nil
  end

  # Get development config (advanced settings, hidden by default)
  def self.development(key = nil)
    return nil unless File.exist?(DEVELOPMENT_FILE)
    config_data = parse_yaml(DEVELOPMENT_FILE)

    return config_data unless key

    keys = key.to_s.split(".")
    config_data&.dig(*keys)
  rescue => e
    Rails.logger.error "SiteConfig.development error: #{e.message}"
    nil
  end

  # Get content config (rendering + search), split out of site.yml. Reads
  # content.yml; if the key isn't there yet, falls back to the pre-split flat
  # key in site.yml so an un-migrated install keeps working.
  def self.content(key = nil)
    config_data = File.exist?(CONTENT_FILE) ? (parse_yaml(CONTENT_FILE) || {}) : {}
    return config_data unless key

    value = config_data.dig(*key.to_s.split("."))
    return value unless value.nil?

    legacy = CONTENT_LEGACY_KEYS[key.to_s]
    legacy ? get(legacy) : nil
  rescue => e
    Rails.logger.error "SiteConfig.content error: #{e.message}"
    nil
  end

  # Get default config (cards, collections)
  def self.default(type, key)
    current("defaults/#{type}")&.config&.[](key.to_s)
  end

  # Get integration config (payments, newsletters, snipcart)
  def self.integration(type, key = nil)
    config = current("integrations/#{type}")&.config
    return config unless key

    keys = key.to_s.split(".")
    config&.dig(*keys)
  end

  # Get feature config (members, podcast, store)
  def self.feature(type, key = nil)
    config = current("features/#{type}")&.config
    return config unless key

    keys = key.to_s.split(".")
    config&.dig(*keys)
  end

  # Check if feature is enabled (file exists)
  def self.feature_enabled?(type)
    File.exist?(FEATURES_PATH.join("#{type}.yml"))
  end

  # Get current config by type. Nil for a type this class doesn't manage —
  # callers already reach through with &., so an unknown type reads as
  # "no config" rather than as the site config.
  def self.current(type = "site")
    file_path = file_path_for(type)
    return unmanaged(type) if file_path.nil?

    Rails.cache.fetch("#{CACHE_KEY_PREFIX}_#{type}") do
      find_by(file_path: file_path.to_s) || create_from_file(type)
    end
  end

  def self.reload!(type = nil)
    reset_file_cache! if type.nil? || type.to_s == "site"

    if type
      Rails.cache.delete("#{CACHE_KEY_PREFIX}_#{type}")
    else
      # Derived, not listed. The hardcoded list this replaced had gone stale —
      # features/music was added and never added here, so reloading "all"
      # quietly left the music config cached.
      db_backed_types.each do |config_type|
        Rails.cache.delete("#{CACHE_KEY_PREFIX}_#{config_type}")
      end
    end
  end

  def self.sync_from_file(type)
    file_path = file_path_for(type)
    return unmanaged(type) if file_path.nil?
    return unless File.exist?(file_path)

    config_data = parse_yaml(file_path)
    site_config = find_or_initialize_by(file_path: file_path.to_s)
    site_config.config = config_data
    site_config.save!

    Rails.cache.delete("#{CACHE_KEY_PREFIX}_#{type}")
    reset_file_cache! if type.to_s == "site"

    # A show or release audience cascades to its episodes' and tracks' files.
    # Editing podcast.yml saves no post, so without this the media index keeps
    # the old answer until something unrelated happens to be saved. Hooked here
    # rather than on reload!, which fires on read paths too.
    Medium.recompute_for_config(type)

    site_config
  rescue => e
    Rails.logger.error "Failed to sync #{type} config: #{e.message}"
    nil
  end

  # Every config type this class serves from the database, discovered from
  # what's actually on disk. Files are the source of truth; these rows are a
  # projection of them, so anything that changes the files has to be able to
  # rebuild the whole projection.
  #
  # `get`, `fonts`, `custom_code` and `development` read their files directly
  # and so are never stale — they're deliberately absent here.
  def self.db_backed_types
    types = []
    types << "site"     if File.exist?(SITE_FILE)
    types << "content"  if File.exist?(CONTENT_FILE)
    types << "fonts"    if File.exist?(FONTS_FILE)
    types << "deploy"   if File.exist?(DEPLOY_FILE)
    types << "security" if File.exist?(SECURITY_FILE)

    types + Dir.glob(DEFAULTS_PATH.join("*.yml")).map { |f| "defaults/#{File.basename(f, '.yml')}" }.sort +
            Dir.glob(FEATURES_PATH.join("*.yml")).map { |f| "features/#{File.basename(f, '.yml')}" }.sort
  end

  def self.sync_all
    db_backed_types.each { |type| sync_from_file(type) }
  end

  def static_generation_enabled
    config.dig("static_generation_enabled") || false
  end

  private

  # A type we don't manage. Logged rather than raised: file_path_for is shared
  # with `current`, which runs on page renders, and ContentWatcher hands it the
  # basename of whatever .yml appears in system/global/ — so a user dropping
  # notes.yml in there would take out a page or the watcher thread. Nil is the
  # honest answer and every caller already treats it as "no config".
  def self.unmanaged(type)
    Rails.logger.warn "[SiteConfig] No config file for type #{type.inspect} — ignoring"
    nil
  end

  # nil for anything unrecognised.
  #
  # This used to fall through to SITE_FILE, which meant an unknown type was
  # answered with the site config instead of an error. Two things were already
  # living in that gap: every `integrations/*` call resolved to site.yml (so
  # four callers that meant to sync an integration were re-syncing site.yml),
  # and ContentWatcher reported "✓ Custom_code config reloaded" while reloading
  # site.yml. Both were invisible precisely because the fallback looked like an
  # answer.
  def self.file_path_for(type)
    case type
    when "site"
      SITE_FILE
    when "fonts"
      FONTS_FILE
    when "content"
      CONTENT_FILE
    when "security"
      SECURITY_FILE
    when "deploy"
      DEPLOY_FILE
    when /^features\//
      filename = type.split("/").last
      FEATURES_PATH.join("#{filename}.yml")
    when /^defaults\//
      filename = type.split("/").last
      DEFAULTS_PATH.join("#{filename}.yml")
    end
  end

  def self.create_from_file(type)
    file_path = file_path_for(type)
    return nil unless File.exist?(file_path)

    config_data = parse_yaml(file_path)
    create!(
      file_path: file_path.to_s,
      config: config_data
    )
  rescue => e
    Rails.logger.error "Failed to load #{type} config: #{e.message}"
    nil
  end

  # Host suffixes that are always local, and so must be served over http.
  # .test and .localhost are reserved for exactly this by RFC 6761, .local
  # by RFC 6762. .roe is ours: roe.sh register maps <name>.roe in /etc/hosts
  # for each install, and it is not a delegated top-level domain.
  LOCAL_HOST_SUFFIXES = %w[.localhost .test .local .roe].freeze

  # True when the configured domain can only be a local address, so
  # site_url must not upgrade it to https.
  #
  # This matters for running several installs side by side: each one is
  # reached at its own hostname (the-briefcase.roe and so on) so the browser keeps
  # their session cookies apart. Without this check such a host would be
  # handed an https:// URL nothing is listening on, and every generated
  # link, mailer URL, and feed entry would point at a dead scheme.
  #
  # Escape hatch: put an explicit scheme in site.yml's url and it is used
  # verbatim, bypassing this guess entirely.
  def self.local_host?(domain)
    host = domain.to_s.downcase.sub(%r{\Ahttps?://}, "").split("/").first.to_s
    host = if host.start_with?("[")
      host[/\A\[([^\]]+)\]/, 1].to_s
    else
      host.split(":").first.to_s
    end

    return true if [ "localhost", "0.0.0.0", "::1" ].include?(host)
    return true if host.match?(/\A127\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/)
    return true if host.match?(/\A10\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/)
    return true if host.match?(/\A192\.168\.\d{1,3}\.\d{1,3}\z/)
    return true if host.match?(/\A172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}\z/)

    LOCAL_HOST_SUFFIXES.any? { |suffix| host.end_with?(suffix) }
  end

  def self.site_url
    domain = current("site")&.config&.dig("url") || "localhost:3000"

    # Remove any trailing slashes
    domain = domain.sub(/\/$/, "")

    # If it already has a protocol, use it as-is
    return domain if domain.match?(/^https?:\/\//)

    # Otherwise, add the appropriate protocol
    if local_host?(domain)
      "http://#{domain}"
    else
      "https://#{domain}"
    end
  end
end
