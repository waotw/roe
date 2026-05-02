require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Roe
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    config.action_mailer.delivery_method = :postmark

    config.action_mailer.postmark_settings = {
      api_token: Rails.application.credentials.postmark_api_token
    }

    # Only allow explicit database specification for migrations
    config.active_record.dump_schema_after_migration = false

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end

# Centralized Site Path Configuration
# This module defines the path to the /site directory
# When Roe is moved to a versioned directory structure (current/),
# this will point to the parent directory's site/ folder
module RoeSitePaths
  # Compute ROE_ROOT at module load time
  # In versioned setup: Rails app is in /roe/current/, site is in /roe/site/
  # In standard setup: Rails app is in /roe/, site is in /roe/site/
  ROE_ROOT = begin
    # Check if site directory exists in parent (versioned structure)
    parent_dir = File.expand_path('..', Rails.root)
    parent_site = File.join(parent_dir, 'site')
    
    # Also check if current directory name suggests we're versioned
    current_dir_name = File.basename(Rails.root)
    
    if current_dir_name == 'current' && File.directory?(parent_site)
      # Versioned structure: we're in /roe/current/, site is in /roe/site/
      parent_dir
    else
      # Standard structure: site is in Rails.root
      Rails.root.to_s
    end
  end

  # SITE_PATH is where all user content lives. Defaults to <ROE_ROOT>/site,
  # overridable via the ROE_SITE_PATH env var. The override exists so the
  # update system's MigrationTester can boot a Rails subprocess pointed
  # at a copy of the production site (under staging/test_site/) and run
  # `db:migrate` against the copy without ever touching the real DB.
  SITE_PATH = ENV['ROE_SITE_PATH'].presence || File.join(ROE_ROOT, 'site')

  # STATIC_SITE_PATH is where static site output goes (outside versioned directory)
  STATIC_SITE_PATH = File.join(ROE_ROOT, 'static_site')

  # Common subdirectories
  SITE_SYSTEM_PATH = File.join(SITE_PATH, 'system')
  SITE_POSTS_PATH = File.join(SITE_PATH, 'posts')
  SITE_PAGES_PATH = File.join(SITE_PATH, 'pages')
  SITE_DOCUMENTATION_PATH = File.join(SITE_PATH, 'documentation')
  SITE_PRODUCTS_PATH = File.join(SITE_PATH, 'products')
  SITE_MEDIA_PATH = File.join(SITE_PATH, 'media')
  SITE_EMAILS_PATH = File.join(SITE_PATH, 'emails')
  SITE_TEMPLATES_PATH = File.join(SITE_PATH, 'templates')
  SITE_LAYOUT_PATH = File.join(SITE_PATH, 'layout')
  SITE_THEME_PATH = File.join(SITE_PATH, 'theme')

  # System subdirectories
  SITE_DB_PATH = File.join(SITE_PATH, 'db')
  SITE_SYSTEM_GLOBAL_PATH = File.join(SITE_SYSTEM_PATH, 'global')
  SITE_SYSTEM_FEATURES_PATH = File.join(SITE_SYSTEM_PATH, 'features')
  SITE_SYSTEM_DEFAULTS_PATH = File.join(SITE_SYSTEM_PATH, 'defaults')
end
