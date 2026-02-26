# Only run in development and production, not during rake tasks or console
unless defined?(Rails::Console) || Rails.env.test? || File.basename($0) == 'rake'
  Rails.application.config.after_initialize do
    # Sync existing content on startup
    ContentSync.sync_all

    # Start the file watcher
    ContentWatcher.start

    puts "🚀 Content management system ready!"
  end
end
