class SiteConfig < ApplicationRecord
  SYSTEM_PATH = Rails.root.join('content', 'system')
  SITE_FILE = SYSTEM_PATH.join('site.yml')
  DEFAULTS_PATH = SYSTEM_PATH.join('defaults')

  CACHE_KEY_PREFIX = 'site_config'

  # Get site-level config
  def self.get(key)
    current('site')&.config&.[](key.to_s)
  end

  # Get default config (cards, collections, etc.)
  def self.default(type, key)
    current("defaults/#{type}")&.config&.[](key.to_s)
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
      Rails.cache.delete_matched("#{CACHE_KEY_PREFIX}_*")
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
    # Sync main site config
    sync_from_file('site') if File.exist?(SITE_FILE)

    # Sync all defaults
    Dir.glob(DEFAULTS_PATH.join('*.yml')).each do |file|
      type = "defaults/#{File.basename(file, '.yml')}"
      sync_from_file(type)
    end
  end

  private

  def self.file_path_for(type)
    if type == 'site'
      SITE_FILE
    else
      # type will be like "defaults/cards"
      filename = type.split('/').last
      DEFAULTS_PATH.join("#{filename}.yml")
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
end
