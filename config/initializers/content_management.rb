# config/initializers/content_management.rb

# Detect if we're running console, runner, or rake commands
is_console = $PROGRAM_NAME.include?("console") || defined?(Rails::Console)
is_runner = caller.any? { |line| line.include?("runner_command.rb") }
is_rake = $PROGRAM_NAME.include?("rake")

should_run = case Rails.env.to_sym
when :production
  # Run for production unless we're in console, runner, or rake
  !is_console && !is_runner && !is_rake
when :development
  # In dev, only run for server
  (defined?(Rails::Server) || ENV["OVERMIND_SOCKET"].present?) && !is_console && !is_runner && !is_rake
else
  false
end

puts "🔧 Content management initializer: #{should_run ? 'ENABLED' : 'DISABLED'}"
puts "   Console: #{is_console}, Runner: #{is_runner}, Rake: #{is_rake}"
puts "   PROGRAM_NAME: #{$PROGRAM_NAME}"

if should_run
  Rails.application.config.after_initialize do
    begin
      if ActiveRecord::Base.connection.table_exists?("posts")
        puts "\n" + "=" * 60
        puts "🚀 Initializing Content Management System"
        puts "=" * 60

        # Regenerate deploy config files if they were wiped by an update.
        # fly.toml and config/deploy.yml live inside current/ and are
        # removed when the updater swaps in a new release. As long as
        # site/system/global/deploy.yml exists (it's in site/, which
        # survives every update), we can regenerate them silently on boot.
        if File.exist?(SiteConfig::DEPLOY_FILE)
          fly_toml   = Rails.root.join("fly.toml")
          kamal_yml  = Rails.root.join("config", "deploy.yml")
          if !fly_toml.exist? || !kamal_yml.exist?
            missing = [ (!fly_toml.exist? ? "fly.toml" : nil), (!kamal_yml.exist? ? "config/deploy.yml" : nil) ].compact
            puts "\n🔄 Restoring missing deploy config#{'s' if missing.size > 1} after update: #{missing.join(', ')}"
            DeployConfigGenerator.new.generate!
            puts "✓ Deploy configs restored"
          end
        end

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
