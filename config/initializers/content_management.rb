unless ENV['SECRET_KEY_BASE_DUMMY'] || defined?(Rails::Console) || Rails.env.test? || File.basename($0) == 'rake'
  Rails.application.config.after_initialize do
    # Only sync if database tables exist
    if ActiveRecord::Base.connection.table_exists?('posts')
      ContentSync.sync_all

      if Rails.env.development?
        ContentWatcher.start
      end

      puts "🚀 Content management system ready!"
    else
      puts "⚠️  Database not ready yet, skipping content sync"
    end
  end
end
