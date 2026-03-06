if defined?(Rails::Server) || ENV['RAILS_ENV'] == 'production'
  Rails.application.config.after_initialize do
    if ActiveRecord::Base.connection.table_exists?('posts')
      ContentSync.sync_all

      if Rails.env.development?
        ContentWatcher.start
      end

      puts "🚀 Content management system ready!"
    end
  end
end
