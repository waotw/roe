if defined?(Puma) && File.basename($0) != 'rake'
  Rails.application.config.after_initialize do
    # Skip if tables don't exist yet (first deploy)
    if ActiveRecord::Base.connection.table_exists?('posts')
      ContentSync.sync_all

      # Only watch files in development
      if Rails.env.development?
        ContentWatcher.start
      end

      puts "🚀 Content management system ready!"
    end
  rescue => e
    # Fail gracefully if something goes wrong during startup
    Rails.logger.error "Content sync failed: #{e.message}"
  end
end
