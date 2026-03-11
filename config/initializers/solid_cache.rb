Rails.application.config.to_prepare do
  SolidCache::Record.connects_to database: { writing: :cache, reading: :cache }
end
