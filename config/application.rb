require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Centralized Site Path Configuration. Defined BEFORE the Application
# class so the credentials path config below can reference it. ROE_ROOT
# is derived from __dir__ rather than Rails.root because Rails.root
# isn't reliably set until Application is fully defined — and
# Rails.application reads credentials very early in boot, before
# initializers run.
module RoeSitePaths
  # config/application.rb is at <Rails app>/config/application.rb, so
  # the Rails app root is one level up.
  RAILS_APP_ROOT = File.expand_path("..", __dir__)

  # In versioned setup: Rails app is in /roe/current/, site is in /roe/site/
  # In standard setup: Rails app is in /roe/, site is in /roe/site/
  #
  # The Roe installer always names the Rails app directory "current".
  # That basename is the authoritative signal for the versioned
  # layout — we deliberately do NOT also require <parent>/site to
  # already exist, because on a fresh install Rails boots BEFORE
  # bin/setup creates site/. Requiring it would silently fall through
  # to "standard" mode and resolve SITE_PATH to current/site, which
  # ContentSync then walks → File.realpath raises ENOENT → boot fails.
  ROE_ROOT = if File.basename(RAILS_APP_ROOT) == "current"
    File.expand_path("..", RAILS_APP_ROOT)   # Versioned: site lives at /roe/site
  else
    RAILS_APP_ROOT                            # Standard: site lives alongside the Rails app
  end

  # SITE_PATH is where all user content lives. Defaults to <ROE_ROOT>/site,
  # overridable via the ROE_SITE_PATH env var. The override exists so the
  # update system's MigrationTester can boot a Rails subprocess pointed
  # at a copy of the production site (under staging/test_site/) and run
  # `db:migrate` against the copy without ever touching the real DB.
  #
  # In RAILS_ENV=test we route everything to <ROE_ROOT>/tmp/test_site/
  # so test runs can write integration configs, sync fixtures, etc.
  # without ever touching the developer's real /site directory. The
  # tmp/ tree is gitignored by Rails default.
  SITE_PATH = ENV["ROE_SITE_PATH"].presence ||
              (ENV["RAILS_ENV"] == "test" ? File.join(ROE_ROOT, "tmp", "test_site")
                                          : File.join(ROE_ROOT, "site"))

  # STATIC_SITE_PATH is where static site output goes (outside versioned directory)
  STATIC_SITE_PATH = File.join(ROE_ROOT, "static_site")

  # Common subdirectories
  SITE_SYSTEM_PATH = File.join(SITE_PATH, "system")
  SITE_POSTS_PATH = File.join(SITE_PATH, "posts")
  SITE_PAGES_PATH = File.join(SITE_PATH, "pages")
  SITE_DOCUMENTATION_PATH = File.join(SITE_PATH, "documentation")
  SITE_PRODUCTS_PATH = File.join(SITE_PATH, "products")
  SITE_MEDIA_PATH = File.join(SITE_PATH, "media")
  SITE_EMAILS_PATH = File.join(SITE_PATH, "emails")
  SITE_TEMPLATES_PATH = File.join(SITE_PATH, "templates")
  SITE_LAYOUT_PATH = File.join(SITE_PATH, "layout")
  SITE_THEME_PATH = File.join(SITE_PATH, "theme")

  # System subdirectories
  SITE_DB_PATH = File.join(SITE_PATH, "db")
  SITE_SYSTEM_GLOBAL_PATH = File.join(SITE_SYSTEM_PATH, "global")
  SITE_SYSTEM_FEATURES_PATH = File.join(SITE_SYSTEM_PATH, "features")
  SITE_SYSTEM_DEFAULTS_PATH = File.join(SITE_SYSTEM_PATH, "defaults")

  # Per-install encryption keys. master.key decrypts credentials.yml.enc,
  # which carries the Active Record Encryption keys used to encrypt 10
  # integration-secret columns (Stripe/Postmark/Snipcart). These live
  # under /site so they're carried by site backups (so a /site restore
  # is self-sufficient) but are excluded from SiteSync to keep dev and
  # prod cryptographically independent.
  SITE_SYSTEM_SECRETS_PATH = File.join(SITE_SYSTEM_PATH, "secrets")

  # Resolve a /site path to its canonical form, following symlinks.
  # On production the Dockerfile sets up `/rails/site` as a symlink to
  # `/data/site` (the persistent volume); without normalization, the
  # admin controllers store the symlink path while the file watcher
  # (Listen) reports the realpath, and content lookups silently
  # mismatch — creating duplicate Post/Page records on every change.
  #
  # Falls back to expand_path when the file doesn't exist (typical
  # for delete handlers, where realpath would raise ENOENT).
  def self.normalize(path)
    File.realpath(path)
  rescue Errno::ENOENT
    File.expand_path(path)
  end
end

# One-time migration: credentials used to live under current/config/
# but now live under /site/system/secrets/ (per-install, backed up,
# survives current/ swaps). Copy them over on first boot after the
# upgrade; no-op once the new location holds them.
#
# Runs at file-load time (before Application is defined) because Rails
# reads credentials very early during Application initialization — we
# need the files at the new path before that happens.
require "fileutils"
begin
  new_secrets_dir   = RoeSitePaths::SITE_SYSTEM_SECRETS_PATH
  legacy_config_dir = File.join(RoeSitePaths::RAILS_APP_ROOT, "config")

  if !File.exist?(File.join(new_secrets_dir, "master.key")) &&
     File.exist?(File.join(legacy_config_dir, "master.key"))
    FileUtils.mkdir_p(new_secrets_dir)
    File.chmod(0o700, new_secrets_dir)

    %w[master.key credentials.yml.enc].each do |fname|
      src = File.join(legacy_config_dir, fname)
      dst = File.join(new_secrets_dir, fname)
      next unless File.exist?(src) && !File.exist?(dst)
      FileUtils.cp(src, dst)
      File.chmod(0o600, dst)
    end

    readme = File.join(new_secrets_dir, "README.txt")
    unless File.exist?(readme)
      File.write(readme,
        "This directory contains your install's encryption keys.\n" \
        "Do NOT copy these files to other Roe installs or share them publicly.\n" \
        "Do ADD this directory to your .gitignore file if your repo is public.\n" \
        "Site backups include these files so a /site restore is self-sufficient.\n" \
        "SiteSync is configured to exclude this directory so dev/prod stay independent.\n")
    end
  end
rescue => e
  warn "[RoeSecrets] One-time migration warning: #{e.class}: #{e.message}"
end

module Roe
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Only allow explicit database specification for migrations
    config.active_record.dump_schema_after_migration = true

    # Silence the "Unpermitted parameters" warning for authenticity_token
    # and commit — these are standard Rails form params (CSRF token and
    # submit button label) that never need to be in permit() and would
    # otherwise appear in the log on every form submission.
    config.action_controller.action_on_unpermitted_parameters = false

    # Per-install encryption keys live under /site/system/secrets/ — see
    # RoeSitePaths::SITE_SYSTEM_SECRETS_PATH for the rationale (carried by
    # site backups, excluded from SiteSync, never mismatch on update). The
    # one-time migration block above pulls them from the legacy
    # current/config/ location on first boot after upgrading; bin/setup
    # generates fresh ones at this path for a brand-new install.
    config.credentials.content_path = Pathname.new(File.join(RoeSitePaths::SITE_SYSTEM_SECRETS_PATH, "credentials.yml.enc"))
    config.credentials.key_path     = Pathname.new(File.join(RoeSitePaths::SITE_SYSTEM_SECRETS_PATH, "master.key"))

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
