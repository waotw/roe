# In config/initializers/content_management.rb

# ONLY run when Puma is actually serving requests
should_run = if ENV['RAILS_ENV'] == 'production'
  puts "✓ Should run: production environment"
  true
elsif Rails.env.development?
  # Check if we're running the server (not console, rake, etc.)
  is_server = defined?(Rails::Server) || ENV['OVERMIND_SOCKET'].present?
  puts "✓ Development environment, server detected: #{is_server}"
  is_server
else
  puts "✗ Not running (not production or development)"
  false
end

puts "Should run content watcher: #{should_run}"

if should_run
  Rails.application.config.after_initialize do
    begin
      if ActiveRecord::Base.connection.table_exists?('posts')
        # Generate default config files if they don't exist
        ConfigGenerator.generate_all

        # Generate default pages if they don't exist
        PageGenerator.generate_defaults

        # Sync all content and configs to database
        ContentSync.sync_all

        if Rails.env.development?
          puts "🎬 Starting content watcher..."
          ContentWatcher.start
        end

        puts "🚀 Content management system ready!"
      end
    rescue => e
      Rails.logger.error "Content sync failed: #{e.message}"
      puts "❌ Content sync failed: #{e.message}"
    end
  end
end
