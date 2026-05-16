class SiteConfig < ApplicationRecord
  SYSTEM_PATH = File.join(RoeSitePaths::SITE_PATH, 'system')
  SITE_PATH = File.join(SYSTEM_PATH, 'global')
  FEATURES_PATH = Pathname.new(File.join(SYSTEM_PATH, 'features'))
  DEFAULTS_PATH = Pathname.new(File.join(SYSTEM_PATH, 'defaults'))

  SITE_FILE = File.join(SITE_PATH, 'site.yml')
  FONTS_FILE = File.join(SITE_PATH, 'fonts.yml')
  DEVELOPMENT_FILE = File.join(SITE_PATH, 'development.yml')
  DEPLOY_FILE = File.join(SITE_PATH, 'deploy.yml')

  CACHE_KEY_PREFIX = 'site_config'

  # Get site-level config
  def self.get(key)
    return nil unless File.exist?(SITE_FILE)
    config_data = YAML.load_file(SITE_FILE)

    # Handle nested keys like 'theme.active'
    keys = key.to_s.split('.')
    config_data&.dig(*keys)
  rescue => e
    Rails.logger.error "SiteConfig.get error: #{e.message}"
    nil
  end

  # Get fonts config
  def self.fonts(key = nil)
    return nil unless File.exist?(FONTS_FILE)
    config_data = YAML.load_file(FONTS_FILE)

    return config_data unless key

    keys = key.to_s.split('.')
    config_data&.dig(*keys)
  rescue => e
    Rails.logger.error "SiteConfig.fonts error: #{e.message}"
    nil
  end

  # Get development config (advanced settings, hidden by default)
  def self.development(key = nil)
    return nil unless File.exist?(DEVELOPMENT_FILE)
    config_data = YAML.load_file(DEVELOPMENT_FILE)

    return config_data unless key

    keys = key.to_s.split('.')
    config_data&.dig(*keys)
  rescue => e
    Rails.logger.error "SiteConfig.development error: #{e.message}"
    nil
  end

  # Get default config (cards, collections)
  def self.default(type, key)
    current("defaults/#{type}")&.config&.[](key.to_s)
  end

  # Get feature config (members, podcast, store)
  def self.feature(type, key = nil)
    config = current("features/#{type}")&.config
    return config unless key

    keys = key.to_s.split('.')
    config&.dig(*keys)
  end

  # Check if feature is enabled (file exists)
  def self.feature_enabled?(type)
    File.exist?(FEATURES_PATH.join("#{type}.yml"))
  end

  # Get current config by type
  def self.current(type = 'site')
    cache_key = "#{CACHE_KEY_PREFIX}_#{type}"

    Rails.cache.fetch(cache_key) do
      file_path = file_path_for(type)
      find_by(file_path: file_path.to_s) || create_from_file(type)
    end
  end

  def self.reload!(type = nil)
    if type
      Rails.cache.delete("#{CACHE_KEY_PREFIX}_#{type}")
    else
      # Clear all config caches
      [
        'site',
        'fonts',
        'defaults/collections',
        'defaults/cards',
        'features/members',
        'features/podcast',
        'features/store'
      ].each do |config_type|
        Rails.cache.delete("#{CACHE_KEY_PREFIX}_#{config_type}")
      end
    end
  end

  def self.sync_from_file(type)
    file_path = file_path_for(type)
    return unless File.exist?(file_path)

    config_data = YAML.load_file(file_path)
    site_config = find_or_initialize_by(file_path: file_path.to_s)
    site_config.config = config_data
    site_config.save!

    Rails.cache.delete("#{CACHE_KEY_PREFIX}_#{type}")
    site_config
  rescue => e
    Rails.logger.error "Failed to sync #{type} config: #{e.message}"
    nil
  end

  def self.sync_all
    # Sync site configs
    sync_from_file('site') if File.exist?(SITE_FILE)
    sync_from_file('fonts') if File.exist?(FONTS_FILE)
    sync_from_file('deploy') if File.exist?(DEPLOY_FILE)

    # Sync all defaults
    Dir.glob(DEFAULTS_PATH.join('*.yml')).each do |file|
      type = "defaults/#{File.basename(file, '.yml')}"
      sync_from_file(type)
    end

    # Sync all features
    Dir.glob(FEATURES_PATH.join('*.yml')).each do |file|
      type = "features/#{File.basename(file, '.yml')}"
      sync_from_file(type)
    end
  end

  def static_generation_enabled
    config.dig('static_generation_enabled') || false
  end

  private

  def self.file_path_for(type)
    case type
    when 'site'
      SITE_FILE
    when 'fonts'
      FONTS_FILE
    when 'deploy'
      DEPLOY_FILE
    when /^features\//
      filename = type.split('/').last
      FEATURES_PATH.join("#{filename}.yml")
    when /^defaults\//
      filename = type.split('/').last
      DEFAULTS_PATH.join("#{filename}.yml")
    else
      SITE_FILE
    end
  end

  def self.create_from_file(type)
    file_path = file_path_for(type)
    return nil unless File.exist?(file_path)

    config_data = YAML.load_file(file_path)
    create!(
      file_path: file_path.to_s,
      config: config_data
    )
  rescue => e
    Rails.logger.error "Failed to load #{type} config: #{e.message}"
    nil
  end

  def self.site_url
    domain = current('site')&.config&.dig('url') || 'localhost:3000'

    # Remove any trailing slashes
    domain = domain.sub(/\/$/, '')

    # If it already has a protocol, use it as-is
    return domain if domain.match?(/^https?:\/\//)

    # Otherwise, add the appropriate protocol
    if domain.include?('localhost') || domain.match?(/^127\.0\.0\.1/)
      "http://#{domain}"
    else
      "https://#{domain}"
    end
  end
end
