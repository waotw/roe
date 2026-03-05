# Skip during asset precompilation (SECRET_KEY_BASE_DUMMY is set during build)
# Skip during rake tasks and console
unless ENV['SECRET_KEY_BASE_DUMMY'] || defined?(Rails::Console) || Rails.env.test? || File.basename($0) == 'rake'
  Rails.application.config.after_initialize do
    # Sync existing content on startup
    ContentSync.sync_all

    # Only start file watcher in development
    if Rails.env.development?
      ContentWatcher.start
    end

    puts "🚀 Content management system ready!"
  end
end
