# config/initializers/content_management.rb

should_run = case Rails.env.to_sym
when :production
  # Only run for web server, not rails runner or console
  defined?(Puma) && !ARGV.include?('runner') && !ARGV.include?('console')
when :development
  # In dev, only run for server
  (defined?(Rails::Server) || ENV['OVERMIND_SOCKET'].present?) && !ARGV.include?('runner') && !ARGV.include?('console')
else
  false
end

puts "🔧 Content management initializer: #{should_run ? 'ENABLED' : 'DISABLED'} (#{$PROGRAM_NAME})"

if should_run
  Rails.application.config.after_initialize do
    begin
      if ActiveRecord::Base.connection.table_exists?('posts')
        puts "\n" + "=" * 60
        puts "🚀 Initializing Content Management System"
        puts "=" * 60

        ConfigGenerator.generate_all
        PageGenerator.generate_defaults
        ContentSync.sync_all

        # Start watcher in BOTH dev and production (single mode = safe)
        puts "\n🎬 Starting content watcher..."
        ContentWatcher.start
        puts "✓ Watcher started - monitoring site/ folder for changes"

        puts "\n" + "=" * 60
        puts "✅ Content Management System Ready!"
        puts "=" * 60 + "\n"
      end
    rescue => e
      Rails.logger.error "Content management initialization failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      puts "\n❌ Content management initialization failed: #{e.message}\n"
    end
  end
end
