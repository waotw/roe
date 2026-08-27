module SiteSync
  # Single source of truth for every on-disk backup location, so a rename,
  # restructure, or hide (e.g. ".backups") happens in exactly one place.
  #
  # Layout (under ROE_ROOT):
  #   backups/
  #     local/                # full /site content snapshots — local restore points
  #     live/
  #       database/           # encrypted live-DB DR bundles (db + keys)
  #       content/            # pre-push live content snapshots (internal, not surfaced)
  #
  # Renamed from the old "site_backups/{local,production}" — see
  # BackupPaths.legacy_root and the boot-time migration in
  # config/application.rb.
  module BackupPaths
    module_function

    ROOT_NAME = "backups".freeze

    # Under RAILS_ENV=test this moves to tmp/, matching how SITE_PATH is
    # redirected (see config/application.rb): a test run must never read,
    # write or prune the developer's real backups. It anchored to ROE_ROOT
    # directly, which meant anything exercising BackupManager pointed at the
    # real directory — and prune! deletes old snapshots.
    def root
      return File.join(RoeSitePaths::ROE_ROOT, "tmp", "test_backups", ROOT_NAME) if Rails.env.test?

      File.join(RoeSitePaths::ROE_ROOT, ROOT_NAME)
    end

    def local
      File.join(root, "local")
    end

    def live
      File.join(root, "live")
    end

    # Encrypted live-database DR bundles (db + master.key + credentials),
    # timestamped, one per sync (retention-capped).
    def live_database
      File.join(live, "database")
    end

    # Pre-push safety snapshots of live *content* — kept as an internal
    # safety net, not surfaced in the UI.
    def live_content
      File.join(live, "content")
    end

    # Pre-rename location, used only by the one-time migration that moves
    # site_backups/local -> backups/local and site_backups/production ->
    # backups/live/content.
    def legacy_root
      File.join(RoeSitePaths::ROE_ROOT, "site_backups")
    end

    def legacy_local
      File.join(legacy_root, "local")
    end

    def legacy_production
      File.join(legacy_root, "production")
    end
  end
end
