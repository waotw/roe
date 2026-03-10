class SiteConfig < ApplicationRecord
  FILE_PATH = Rails.root.join('content', 'system', 'site.yml')
  CACHE_KEY = 'site_config_current'

  def self.current
    Rails.cache.fetch(CACHE_KEY) do
      find_by(file_path: FILE_PATH.to_s) || create_from_file
    end
  end

  def self.get(key)
    current&.config&.[](key.to_s)
  end

  def self.reload!
    Rails.cache.delete(CACHE_KEY)
    current
  end

  def self.create_from_file
    return nil unless File.exist?(FILE_PATH)

    config_data = YAML.load_file(FILE_PATH)
    create!(
      file_path: FILE_PATH.to_s,
      config: config_data
    )
  rescue => e
    Rails.logger.error "Failed to load site config: #{e.message}"
    nil
  end

  def self.sync_from_file
    return unless File.exist?(FILE_PATH)

    config_data = YAML.load_file(FILE_PATH)
    site_config = find_or_initialize_by(file_path: FILE_PATH.to_s)
    site_config.config = config_data
    site_config.save!

    Rails.cache.delete(CACHE_KEY)  # Clear cache instead of instance variable
    site_config
  rescue => e
    Rails.logger.error "Failed to sync site config: #{e.message}"
    nil
  end
end
