module RoeUpdater
  class UpdateOrchestrator
    STEPS = [
      { name: "validating",         percent: 5,   description: "Validating update prerequisites" },
      { name: "backing_up_db",      percent: 15,  description: "Creating database backup" },
      { name: "downloading",        percent: 30,  description: "Downloading new version" },
      { name: "testing",            percent: 50,  description: "Testing migrations" },
      { name: "migrating",          percent: 70,  description: "Running production migrations" },
      { name: "switching",          percent: 85,  description: "Switching to new version" },
      { name: "preserving_secrets", percent: 86,  description: "Preserving per-install secrets" },
      { name: "syncing_root_files", percent: 87,  description: "Syncing root-level files" },
      { name: "writing_version",    percent: 89,  description: "Updating VERSION files" },
      { name: "building_assets",    percent: 92,  description: "Building assets" },
      { name: "restarting",         percent: 95,  description: "Restarting server" },
      { name: "completed",          percent: 100, description: "Update complete" }
    ].freeze

    # Files whose source-of-truth lives in current/ but need to appear
    # at ROE_ROOT/ for users (and for the launcher script). These get
    # copied out after every successful switch so updates pick up new
    # versions of the launcher / docs without manual intervention.
    ROOT_SYNC_FILES = %w[roe.sh README.md AGENTS.md].freeze

    # Files that live INSIDE current/ but are per-install (gitignored,
    # never in the cloned tag) and so don't survive the SwitchManager
    # rename. We copy them across from current.backup/ → current/ after
    # the swap so they aren't regenerated to new values, which would:
    #   - production: leave the new container without master.key, so
    #     credentials.yml.enc can't be decrypted and the app refuses
    #     to boot.
    #   - development: regenerate tmp/development_secret.txt to a new
    #     value, which rotates Rails' session secret_key_base and
    #     invalidates every existing session cookie — the user gets
    #     signed out the moment they restart on the new code.
    PRESERVED_FROM_OLD_CURRENT = %w[
      config/master.key
      tmp/development_secret.txt
    ].freeze

    class << self
      def start_update(to_version, status_record)
        @status = status_record
        @version = to_version

        execute_step(:validating) { validate_prerequisites }
        execute_step(:backing_up_db) { BackupManager.backup_databases(@status) }
        execute_step(:downloading) { Downloader.download_version(@version, @status) }
        execute_step(:testing) { MigrationTester.test_migrations(@status) }
        execute_step(:migrating) { run_production_migrations }
        execute_step(:switching) { SwitchManager.switch_versions(@status) }
        execute_step(:preserving_secrets) { preserve_secrets }
        execute_step(:syncing_root_files) { sync_root_files }
        execute_step(:writing_version) { write_version_files }
        execute_step(:building_assets) { build_assets }
        execute_step(:restarting) { restart_server }

        complete_update
      rescue => e
        handle_failure(e)
      end

      private

      def execute_step(step_name)
        step = STEPS.find { |s| s[:name] == step_name.to_s }

        @status.update!(
          current_step: step[:description],
          progress_percent: step[:percent]
        )

        log("Starting: #{step[:description]}")

        begin
          yield
          log("Completed: #{step[:description]}")
        rescue => e
          log("Failed at #{step[:description]}: #{e.message}")
          raise
        end
      end

      def validate_prerequisites
        unless git_available?
          raise "Git is not available. Please install Git to perform updates."
        end

        # staging/ is transient — created by Downloader, consumed by
        # SwitchManager's rename. It should be absent (or at worst
        # empty) when a new update starts. Non-empty content here
        # means either an update is in progress or a previous run
        # crashed without cleanup; either way we don't want to clobber
        # whatever's there.
        staging = File.join(RoeSitePaths::ROE_ROOT, "staging")
        if Dir.exist?(staging) && !Dir.empty?(staging)
          raise "Staging directory has unexpected content (#{Dir.children(staging).size} items). " \
                "Either an update is in progress, or a previous run crashed — clean up #{staging} manually."
        end
      end

      def run_production_migrations
        log("Running production migrations...")

        # Run from staging/, not current/. At this point the new code +
        # new migration files are still in staging/ — the switch hasn't
        # happened yet. Running from current/ would silently no-op
        # (no new migration files visible) and the new app would boot
        # against an unmigrated schema after the switch.
        staging_app = File.join(RoeSitePaths::ROE_ROOT, "staging")

        # Inherit the parent's Rails.env. In real production updates
        # this is `production` (and credentials are available); in dev
        # tests this is `development` (and we don't need prod creds).
        # Hardcoding production fails in dev with "Missing
        # secret_key_base" because the parent doesn't have a master.key.
        rails_env = Rails.env
        migrate_cmd = "cd '#{staging_app}' && RAILS_ENV=#{rails_env} bundle exec rails db:migrate 2>&1"
        output = nil

        Bundler.with_original_env do
          output = `#{migrate_cmd}`
        end

        unless $?.success?
          raise "Production migration failed: #{output}"
        end

        log("Production migrations completed")
      end

      # Copy per-install secrets from the previous current/ (now
      # current.backup/) into the freshly-switched current/. See the
      # PRESERVED_FROM_OLD_CURRENT comment above for why each path
      # matters. Missing source files are silently skipped — an
      # install that never had a dev_secret yet doesn't need one
      # propagated. Missing destination directories are created.
      def preserve_secrets
        old_current = File.join(RoeSitePaths::ROE_ROOT, "current.backup")
        new_current = File.join(RoeSitePaths::ROE_ROOT, "current")

        preserved = []
        PRESERVED_FROM_OLD_CURRENT.each do |relpath|
          source = File.join(old_current, relpath)
          dest   = File.join(new_current, relpath)
          next unless File.exist?(source)

          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(source, dest)
          preserved << relpath
        end

        if preserved.any?
          log("✓ Preserved per-install secrets: #{preserved.join(', ')}")
        else
          log("⊘ No per-install secrets to preserve")
        end
      end

      # Copy root-level companion files (launcher script + top-level
      # docs) from the freshly-switched current/ up to ROE_ROOT/. These
      # files are versioned with Roe but need to be visible at the
      # project root — the launcher because users invoke `./roe.sh`
      # from there, the docs so `cat README.md` works without diving
      # into current/. Missing source files are skipped with a warning
      # so an older Roe distribution that doesn't ship one of these
      # doesn't break the update.
      def sync_root_files
        ROOT_SYNC_FILES.each do |filename|
          source = File.join(RoeSitePaths::ROE_ROOT, "current", filename)
          dest   = File.join(RoeSitePaths::ROE_ROOT, filename)

          unless File.exist?(source)
            log("⊘ #{filename} not present in current/, skipping")
            next
          end

          FileUtils.cp(source, dest)
          log("✓ Synced #{filename} → ROE_ROOT")
        end
      end

      # Refresh BOTH VERSION files so they report the new version
      # after the swap:
      #
      #   ROE_ROOT/VERSION  — what dev installs read via VersionChecker
      #                       (and what the launcher script greps for in
      #                       `roe.sh status`)
      #   current/VERSION   — what production Docker builds copy into
      #                       /rails/VERSION at image-build time, so the
      #                       production container's VersionChecker
      #                       reports the right version too
      #
      # Writing authoritatively from @version rather than reading from
      # the cloned tag's current/VERSION means a Roe distribution
      # whose tag content has a stale current/VERSION (developer forgot
      # to bump before tagging) still ends up consistent on disk after
      # an update — defensive against tag-time mistakes.
      def write_version_files
        data = {
          "version"      => @version,
          "release_date" => Date.today.iso8601,
        }

        [
          File.join(RoeSitePaths::ROE_ROOT, "VERSION"),
          File.join(RoeSitePaths::ROE_ROOT, "current", "VERSION"),
        ].each do |path|
          existing = File.exist?(path) ? (YAML.load_file(path) || {}) : {}
          File.write(path, existing.merge(data).to_yaml)
          log("✓ Wrote VERSION file: #{path.sub(RoeSitePaths::ROE_ROOT, '')} → #{@version}")
        end
      end

      # Compile build-time assets (Tailwind CSS, anything else
      # `assets:precompile` invokes via prependable rake hooks). The
      # build outputs (e.g. app/assets/builds/tailwind.css) are
      # gitignored as derived artifacts, so a fresh clone has the
      # source files but not the compiled CSS — Propshaft 500s on the
      # next request without this step. assets:precompile is the most
      # general entry point: tailwindcss-rails hooks `tailwindcss:build`
      # into it automatically, and it's a no-op for asset types that
      # aren't configured.
      def build_assets
        current_app = File.join(RoeSitePaths::ROE_ROOT, "current")
        rails_env = Rails.env

        cmd = "cd '#{current_app}' && RAILS_ENV=#{rails_env} bundle exec rails assets:precompile 2>&1"
        output = nil

        Bundler.with_original_env do
          output = `#{cmd}`
        end

        unless $?.success?
          raise "Asset compilation failed: #{output}"
        end

        log("Assets compiled")
      end

      def restart_server
        log("Initiating server restart...")

        # Outside production we don't kill the server — there's no
        # process supervisor to bring it back up, so exiting would just
        # leave a dead Puma. Tell the user to restart by hand.
        unless Rails.env.production?
          log("⚠️  Manual restart required to load the new version: run `./roe.sh restart`")
          return
        end

        # In production we trust a supervisor (systemd / kamal / fly
        # machine config) to relaunch us. Schedule the exit a few
        # seconds out so the orchestrator's complete_update call (and
        # this status update) is durably persisted before we die.
        Thread.new do
          sleep 5
          Rails.logger.info "[RoeUpdater] Exiting for supervised restart"
          exit!(0)
        end

        log("Server restart scheduled in 5 seconds (supervisor will relaunch)")
      end

      def complete_update
        @status.update!(
          status: "completed",
          current_step: "Update completed successfully",
          completed_at: Time.current
        )

        BackupManager.cleanup_update_backups
        SwitchManager.cleanup_backup

        log("✓ Update completed successfully!")
      end

      def handle_failure(error)
        log("Update failed: #{error.message}")
        log("Initiating automatic rollback...")

        begin
          # Pass @status so restore_databases finds the timestamp from
          # THIS update's backup (stamped during backup_databases),
          # rather than guessing at the most recent one on disk.
          BackupManager.restore_databases(@status)
          SwitchManager.rollback
          # Wipe the staging clone too — otherwise the next update
          # attempt will fail validate_prerequisites' "non-empty
          # staging/" check and the user has to clean it up by hand.
          Downloader.cleanup_staging

          @status.update!(
            status: "rolled_back",
            error_message: error.message,
            current_step: "Rolled back to previous version"
          )

          log("Rollback completed")
        rescue => rollback_error
          log("CRITICAL: Rollback failed: #{rollback_error.message}")
          @status.update!(
            status: "failed",
            error_message: "#{error.message}. Rollback also failed: #{rollback_error.message}",
            current_step: "CRITICAL: Manual intervention required"
          )
        end
      end

      def log(message)
        timestamp = Time.current.strftime("%H:%M:%S")
        current_log = @status.log || ""
        @status.update!(log: current_log + "[#{timestamp}] #{message}\n")
        Rails.logger.info "[RoeUpdater] #{message}"
      end

      def git_available?
        system("which git > /dev/null 2>&1")
      end
    end
  end
end
