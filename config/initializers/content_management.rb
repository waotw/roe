# ONLY run when Puma is actually serving requests
should_run = if ENV['RAILS_ENV'] == 'production'
  true
elsif Rails.env.development?
  # Check if we're running the server (not console, rake, etc.)
  defined?(Rails::Server) || ENV['OVERMIND_SOCKET'].present?
else
  false
end

if should_run
  Rails.application.config.after_initialize do
    begin
      if ActiveRecord::Base.connection.table_exists?('posts')
        ContentSync.sync_all

        if Rails.env.development?
          ContentWatcher.start
        end

        puts "🚀 Content management system ready!"
      end
    rescue => e
      Rails.logger.error "Content sync failed: #{e.message}"
    end
  end
end

# # ONLY run when Puma is actually serving requests
# if ENV['RAILS_ENV'] == 'production' ||
#    (Rails.env.development? && ARGV.any? { |arg| arg == 'server' || arg == 's' })

#   Rails.application.config.after_initialize do
#     begin
#       if ActiveRecord::Base.connection.table_exists?('posts')
#         ContentSync.sync_all

#         if Rails.env.development?
#           ContentWatcher.start
#         end

#         puts "🚀 Content management system ready!"
#       end
#     rescue => e
#       Rails.logger.error "Content sync failed: #{e.message}"
#     end
#   end
# end
