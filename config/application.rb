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

# One-time migration: the backups directory was renamed from
# "site_backups/{local,production}" to "backups/{local,live/content}" (with
# live/database/ added for encrypted DB DR bundles). Move any existing
# folders on first boot after the upgrade; idempotent once moved.
begin
  __legacy_backups = File.join(RoeSitePaths::ROE_ROOT, "site_backups")
  __new_backups    = File.join(RoeSitePaths::ROE_ROOT, "backups")
  if File.directory?(__legacy_backups)
    FileUtils.mkdir_p(File.join(__new_backups, "live"))
    {
      File.join(__legacy_backups, "local")      => File.join(__new_backups, "local"),
      File.join(__legacy_backups, "production") => File.join(__new_backups, "live", "content")
    }.each do |src, dst|
      next unless File.directory?(src)
      next if File.exist?(dst)
      FileUtils.mkdir_p(File.dirname(dst))
      FileUtils.mv(src, dst)
      warn "[RoeBackups] Migrated #{src} → #{dst}"
    end
    # Drop the old wrapper only if we emptied it (any stray files stay put).
    FileUtils.rmdir(__legacy_backups) if File.directory?(__legacy_backups) && Dir.empty?(__legacy_backups)
  end
rescue => e
  warn "[RoeBackups] backups dir migration warning: #{e.class}: #{e.message}"
end

# ── Pending DR restore (staged via the admin upload) ───────────────────
# If an admin staged a database restore (SiteSync::PendingRestore), apply it
# HERE — at boot, before ActiveRecord opens the DB — so we never overwrite the
# live database while it's in use. The previous DB is preserved as a
# .pre-restore-<ts> copy for undo. Runs on every host. Mirrors
# SiteSync::PendingRestore.apply_if_present! (which the tests cover) — the
# logic is inlined because autoloading isn't available this early in boot.
#
# Restore is DB-ONLY: encryption credentials are NOT swapped automatically
# (doing so once clobbered a live site — see RoeSecrets::Bootstrap). We drop a
# plaintext ".restore-check-needed" marker so a post-boot self-check can verify
# the restored DB's encrypted data is readable and, if not, offer the backup's
# parked credentials. Keep the marker path in sync with SiteSync::RestoreCheck.
begin
  require "fileutils"
  __roe_ts   = Time.now.strftime("%Y%m%d%H%M%S")
  __roe_db   = File.join(RoeSitePaths::SITE_DB_PATH, Rails.env, "#{Rails.env}.sqlite3")
  __roe_pend = "#{__roe_db}.restore-pending"
  if File.exist?(__roe_pend)
    FileUtils.mkdir_p(File.dirname(__roe_db))
    FileUtils.mv(__roe_db, "#{__roe_db}.pre-restore-#{__roe_ts}") if File.exist?(__roe_db)
    FileUtils.mv(__roe_pend, __roe_db)
    [ "#{__roe_db}-wal", "#{__roe_db}-shm" ].each { |f| FileUtils.rm_f(f) }
    File.write(File.join(RoeSitePaths::SITE_DB_PATH, ".restore-check-needed"), __roe_ts)
    warn "[RoeRestore] Applied staged database restore → #{__roe_db}"
  end
rescue => e
  warn "[RoeRestore] pending restore swap warning: #{e.class}: #{e.message}"
end

# ── Apply backup credentials (explicit, validated, revertible) ─────────
# The admin asked to install the DR bundle's parked credentials (the restored
# DB's encrypted data wasn't readable with this host's current ones). Do it
# HERE, before the secret bootstrap / Rails reads credentials. Install the
# parked pair, then VALIDATE (must decrypt to an AR primary_key). Keep it if
# valid; otherwise REVERT to the previous pair so the site stays up, and flag
# the failure. Mirrors SiteSync::PendingRestore.apply_backup_credentials!; keep
# marker paths in sync with SiteSync::RestoreCheck.
begin
  require "fileutils"
  require "active_support/encrypted_configuration"
  __sec = RoeSitePaths::SITE_SYSTEM_SECRETS_PATH
  __req = File.join(__sec, ".apply-backup-credentials")
  if File.exist?(__req)
    __ts    = Time.now.strftime("%Y%m%d%H%M%S")
    __saved = {}
    %w[master.key credentials.yml.enc].each do |__f|
      __from = File.join(__sec, "#{__f}.from-backup")
      next unless File.exist?(__from)
      __live = File.join(__sec, __f)
      if File.exist?(__live)
        __pre = "#{__live}.pre-restore-#{__ts}"
        FileUtils.cp(__live, __pre)
        __saved[__f] = __pre
      end
      FileUtils.cp(__from, __live)
      File.chmod(0o600, __live)
    end

    __enc = ActiveSupport::EncryptedConfiguration.new(
      config_path: File.join(__sec, "credentials.yml.enc"),
      key_path:    File.join(__sec, "master.key"),
      env_key:     "RAILS_MASTER_KEY", raise_if_missing_key: false
    )
    __ok = (__enc.config.dig(:active_record_encryption, :primary_key).present? rescue false)

    __failed_marker = File.join(RoeSitePaths::SITE_DB_PATH, ".restore-credentials-apply-failed")
    if __ok
      %w[master.key credentials.yml.enc].each { |__f| FileUtils.rm_f(File.join(__sec, "#{__f}.from-backup")) }
      FileUtils.rm_f(__failed_marker)
      File.write(File.join(RoeSitePaths::SITE_DB_PATH, ".restore-check-needed"), __ts) # re-probe post-boot
      warn "[RoeRestore] Applied backup credentials (validated)."
    else
      __saved.each { |__f, __pre| FileUtils.cp(__pre, File.join(__sec, __f)); FileUtils.rm_f(__pre) }
      File.write(__failed_marker, __ts)
      warn "[RoeRestore] Backup credentials did NOT validate — reverted to the previous credentials."
    end
    FileUtils.rm_f(__req)
  end
rescue => e
  warn "[RoeRestore] apply-backup-credentials warning: #{e.class}: #{e.message}"
end

# Skip the disk-based bootstrap entirely when running on Fly.
# Fly Machines get their secrets injected as env vars from `fly
# secrets set` — same values across every Machine in the app —
# so per-Machine disk-based generation would defeat the purpose
# (each Machine has its own volume, so each Machine would generate
# its own divergent keys, and a user's session cookie signed by
# Machine A would fail verification on Machine B). FLY_APP_NAME
# is auto-injected on every Fly Machine and never present on
# Kamal containers or local dev, so it's a reliable per-environment
# signal. See `bin/rails roe:fly:sync_secrets` for the rake task
# that populates the Fly secret store from a local install.
unless ENV["FLY_APP_NAME"].present?
# Bootstrap & self-heal Roe's per-install secrets at boot, before
# Rails reads them. Three scenarios we have to handle, all here in
# one pass, all idempotent:
#
#   1. Fresh container deploy with empty /site volume — no
#      master.key, no credentials.yml.enc. We generate both,
#      seeding both secret_key_base and active_record_encryption
#      keys into the new credentials file. This is the "just
#      deploys cleanly to a new droplet" path; bin/setup never
#      runs in a container, so the boot has to do it.
#
#   2. Upgrade-in-place from an older Roe where bin/setup populated
#      active_record_encryption keys but not secret_key_base. We
#      add secret_key_base to the existing credentials file; AR
#      encryption keys are left untouched (regenerating them would
#      destroy decryption of already-encrypted DB columns).
#
#   3. Steady state — everything already present. Loop exits with
#      no writes, no warnings.
#
# Runs at file-load time (before `Application` is defined) for the
# same reason as the legacy-migration block above: Rails reads
# credentials very early during Application init.
#
# The one thing we DON'T do: silently regenerate an existing
# master.key or an existing secret_key_base. master.key is the
# decryption key for any AR-encrypted columns already in the DB
# (Stripe / Postmark / Snipcart secrets); regenerating would brick
# all of them. secret_key_base regeneration would invalidate every
# session cookie. Both are write-once at install time.
#
# If you see the "Generated fresh master.key" warning on every
# boot, your persistent volume isn't mounted where SITE_PATH
# resolves to — each container restart is starting with an empty
# /site and regenerating, which means encrypted data written by a
# previous boot is no longer decryptable. Fix the volume mount.
# Extracted to a tested helper (see lib/roe_secrets/bootstrap.rb) so its
# "never overwrite credentials we can't decrypt" guard is regression-covered.
# require_relative (not autoload) because this runs before Zeitwerk is ready.
require_relative "../lib/roe_secrets/bootstrap"
begin
  RoeSecrets::Bootstrap.run!(
    secrets_dir: RoeSitePaths::SITE_SYSTEM_SECRETS_PATH,
    roe_root:    RoeSitePaths::ROE_ROOT,
    site_path:   RoeSitePaths::SITE_PATH
  )
rescue => e
  warn "[RoeSecrets] secret bootstrap warning: #{e.class}: #{e.message}"
end
end # unless ENV["FLY_APP_NAME"].present?

module Roe
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks roe_secrets])

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

    # Fly path for AR encryption keys: read from env vars instead of
    # credentials.yml.enc. Lets every Machine in a multi-Machine app
    # share the same encryption keys (so Stripe API keys written by
    # Machine A are decryptable by Machine B) without needing a
    # synchronized credentials file across per-Machine volumes.
    #
    # Kamal containers and local dev (no FLY_APP_NAME) fall through
    # to Rails' default behaviour of reading these from credentials,
    # so this branch is invisible there.
    #
    # The three env vars are populated by `bin/rails roe:fly:sync_secrets
    # APP=…`, which reads the local install's credentials and pushes
    # the keys to Fly's secret store. See lib/tasks/fly.rake.
    if ENV["FLY_APP_NAME"].present?
      config.active_record.encryption.primary_key         = ENV["AR_ENCRYPTION_PRIMARY_KEY"]
      config.active_record.encryption.deterministic_key   = ENV["AR_ENCRYPTION_DETERMINISTIC_KEY"]
      config.active_record.encryption.key_derivation_salt = ENV["AR_ENCRYPTION_KEY_DERIVATION_SALT"]
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
