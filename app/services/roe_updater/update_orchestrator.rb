module RoeUpdater
  class UpdateOrchestrator
    STEPS = [
      { name: 'validating',         percent: 5,   description: 'Validating update prerequisites' },
      { name: 'backing_up_db',      percent: 15,  description: 'Creating database backup' },
      { name: 'backing_up_site',    percent: 25,  description: 'Creating full site backup' },
      { name: 'downloading',        percent: 40,  description: 'Downloading new version' },
      { name: 'testing',            percent: 55,  description: 'Testing migrations' },
      { name: 'migrating',          percent: 70,  description: 'Running production migrations' },
      { name: 'switching',          percent: 85,  description: 'Switching to new version' },
      { name: 'syncing_root_files', percent: 87,  description: 'Syncing root-level files' },
      { name: 'writing_version',    percent: 89,  description: 'Updating VERSION file' },
      { name: 'building_assets',    percent: 92,  description: 'Building assets' },
      { name: 'restarting',         percent: 95,  description: 'Restarting server' },
      { name: 'completed',          percent: 100, description: 'Update complete' }
    ].freeze

    # Files whose source-of-truth lives in current/ but need to appear
    # at ROE_ROOT/ for users (and for the launcher script). These get
    # copied out after every successful switch so updates pick up new
    # versions of the launcher / docs without manual intervention.
    ROOT_SYNC_FILES = %w[roe.sh README.md AGENTS.md].freeze

    class << self
      def start_update(to_version, status_record)
        @status = status_record
        @version = to_version

        execute_step(:validating) { validate_prerequisites }
        execute_step(:backing_up_db) { BackupManager.backup_databases(@status) }
        execute_step(:backing_up_site) { BackupManager.backup_full_site(@status) }
        execute_step(:downloading) { Downloader.download_version(@version, @status) }
        execute_step(:testing) { MigrationTester.test_migrations(@status) }
        execute_step(:migrating) { run_production_migrations }
        execute_step(:switching) { SwitchManager.switch_versions(@status) }
        execute_step(:syncing_root_files) { sync_root_files }
        execute_step(:writing_version) { write_root_version_file }
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
        staging = File.join(RoeSitePaths::ROE_ROOT, 'staging')
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
        staging_app = File.join(RoeSitePaths::ROE_ROOT, 'staging')

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
          source = File.join(RoeSitePaths::ROE_ROOT, 'current', filename)
          dest   = File.join(RoeSitePaths::ROE_ROOT, filename)

          unless File.exist?(source)
            log("⊘ #{filename} not present in current/, skipping")
            next
          end

          FileUtils.cp(source, dest)
          log("✓ Synced #{filename} → ROE_ROOT")
        end
      end

      # Refresh ROE_ROOT/VERSION so the launcher and VersionChecker
      # report the new version after the swap. We write authoritatively
      # from the orchestrator (which knows @version) rather than copying
      # from current/VERSION — that way a Roe distribution doesn't need
      # to ship a separate root-level VERSION; the file gets created/
      # rewritten on every successful update.
      def write_root_version_file
        version_path = File.join(RoeSitePaths::ROE_ROOT, 'VERSION')

        existing = File.exist?(version_path) ? (YAML.load_file(version_path) || {}) : {}
        updated = existing.merge(
          'version'      => @version,
          'release_date' => Date.today.iso8601
        )

        File.write(version_path, updated.to_yaml)
        log("Wrote VERSION file: #{@version}")
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
        current_app = File.join(RoeSitePaths::ROE_ROOT, 'current')
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
          status: 'completed',
          current_step: 'Update completed successfully',
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
          BackupManager.restore_databases
          SwitchManager.rollback
          BackupManager.cleanup_update_backups
          # Wipe the staging clone too — otherwise the next update
          # attempt will fail validate_prerequisites' "non-empty
          # staging/" check and the user has to clean it up by hand.
          Downloader.cleanup_staging

          @status.update!(
            status: 'rolled_back',
            error_message: error.message,
            current_step: "Rolled back to previous version"
          )

          log("Rollback completed")
        rescue => rollback_error
          log("CRITICAL: Rollback failed: #{rollback_error.message}")
          @status.update!(
            status: 'failed',
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
        system('which git > /dev/null 2>&1')
      end
    end
  end
end
