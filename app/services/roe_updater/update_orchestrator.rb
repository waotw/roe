require "shellwords"

module RoeUpdater
  class UpdateOrchestrator
    STEPS = [
      { name: "validating",         percent: 5,   description: "Validating update prerequisites" },
      { name: "backing_up_db",      percent: 15,  description: "Creating database backup" },
      { name: "downloading",        percent: 30,  description: "Downloading new version" },
      { name: "testing",            percent: 50,  description: "Testing migrations" },
      { name: "migrating",          percent: 70,  description: "Running database migrations" },
      { name: "switching",          percent: 85,  description: "Switching to new version" },
      { name: "preserving_secrets", percent: 86,  description: "Preserving per-install secrets" },
      { name: "syncing_root_files", percent: 87,  description: "Syncing root-level files" },
      { name: "syncing_docs",       percent: 88,  description: "Syncing bundled documentation" },
      { name: "writing_version",    percent: 89,  description: "Updating VERSION files" },
      { name: "installing_gems",    percent: 90,  description: "Installing required gems" },
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
    # the swap so they aren't regenerated to new values, which would
    # rotate Rails' session secret_key_base and invalidate every
    # existing session cookie — the user gets signed out the moment
    # they restart on the new code.
    #
    # Rails 8 renamed `tmp/development_secret.txt` to `tmp/local_secret.txt`
    # (now used in BOTH development and test). This list previously
    # preserved the old name, which silently no-op'd post-Rails-7.1 —
    # which is why sessions started dying on every update.
    #
    # master.key and credentials.yml.enc used to live here too, but
    # they're now under /site/system/secrets/ (per-install, carried by
    # backups, never touched by current/ swaps). See config/application.rb
    # for the path config and bin/setup for the generation flow.
    PRESERVED_FROM_OLD_CURRENT = %w[
      tmp/local_secret.txt
    ].freeze

    class << self
      def start_update(to_version, status_record)
        @status = status_record
        @version = to_version

        execute_step(:validating) { validate_prerequisites }
        execute_step(:backing_up_db) { BackupManager.backup_databases(@status) }
        execute_step(:downloading) { Downloader.download_version(@version, @status) }
        execute_step(:testing) { MigrationTester.test_migrations(@status) }
        execute_step(:migrating) { run_migrations }
        execute_step(:switching) { SwitchManager.switch_versions(@status) }
        execute_step(:preserving_secrets) { preserve_secrets }
        execute_step(:syncing_root_files) { sync_root_files }
        execute_step(:syncing_docs) { sync_docs }
        execute_step(:writing_version) { write_version_files }
        execute_step(:installing_gems) { install_gems }
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

      # Apply pending migrations against the development database.
      #
      # This method only ever runs in development — by design. Two
      # guards make that true:
      #
      #   1. Admin::UpdatesController#block_in_production redirects
      #      every action in production, so the in-app updater never
      #      reaches this code in a prod container.
      #   2. The Updates & Deploy nav link is hidden in production
      #      too, so users don't get nudged toward a path that would
      #      no-op.
      #
      # Production databases are migrated as part of the deploy flow
      # (Kamal pushes a new Docker image; Fly does the same on its
      # release_command), NOT here. The in-app updater is purely for
      # the developer's local dev install and its local SQLite.
      #
      # RAILS_ENV is hardcoded to `development` rather than read from
      # Rails.env to close a footgun: if someone ever booted the dev
      # install with RAILS_ENV=production (testing prod config locally,
      # say), reading Rails.env would have the updater migrate the
      # local production SQLite instead of the dev one. Pinning here
      # means "no matter what env the running process is in, the
      # migration step targets development."
      #
      # ROE_SITE_PATH is passed explicitly so the staging subprocess
      # finds the real /site directory. Without it, the subprocess's
      # RoeSitePaths::ROE_ROOT resolves to <staging> (because
      # File.basename(Rails.root) is "staging", not "current"), and
      # SITE_PATH points at <staging>/site which doesn't exist —
      # SQLite would silently create a fresh empty DB there and the
      # migration would apply to nothing meaningful.
      def run_migrations
        log("Running database migrations...")

        staging_app = File.join(RoeSitePaths::ROE_ROOT, "staging")
        site_path   = RoeSitePaths::SITE_PATH

        migrate_cmd = "cd '#{staging_app}' && " \
                      "RAILS_ENV=development " \
                      "ROE_SITE_PATH='#{site_path}' " \
                      "bundle exec rails db:migrate 2>&1"
        output = nil

        Bundler.with_original_env do
          output = `#{migrate_cmd}`
        end

        unless $?.success?
          raise "Database migration failed: #{output}"
        end

        log("Database migrations completed")
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

      # Mirror the bundled documentation subtree from the new code
      # into the user's site/ tree. The CONTRACT with users is:
      #
      #   Everything inside /site/documentation/roe/ is owned by Roe
      #   and is REPLACED on every update — files added, files
      #   updated, files removed from the tag all reflect immediately
      #   in the user's docs. To keep a custom version of a Roe doc,
      #   move it OUT of the roe/ subfolder (e.g. into
      #   /site/documentation/my-notes/). Anything outside roe/ is
      #   untouched, forever.
      #
      # rsync --delete enforces the mirror: docs deprecated/renamed
      # in this release disappear from the user's tree too, so the
      # rendered docs site can't drift out of sync with the bundled
      # set. The destination is created if missing (handles installs
      # predating this feature where /site/documentation/roe/ may
      # not exist yet).
      #
      # NOT rolled back by handle_failure on a failed update: docs
      # aren't critical state and snapshotting the subtree on every
      # update is overkill. Worst case, a failed update leaves the
      # user on the previous code with the new docs, which renders
      # fine in practice — the previous code can read the new docs
      # without issue, just may miss any feature-specific updates.
      def sync_docs
        source = File.join(
          RoeSitePaths::ROE_ROOT, "current",
          "lib", "site_templates", "minimum", "documentation", "roe"
        )
        dest = File.join(RoeSitePaths::SITE_PATH, "documentation", "roe")

        unless Dir.exist?(source)
          log("⊘ Bundled docs subtree not found at #{source}, skipping")
          return
        end

        FileUtils.mkdir_p(dest)

        # `-c` makes rsync compare by content checksum rather than the
        # default size + mtime check. Without it, every doc shows as
        # "changed" on every update because the release-archive
        # extraction stamps fresh mtimes on every file — even ones whose
        # content didn't actually change between releases. With `-c`,
        # unchanged docs stay untouched on disk (their previous mtime
        # preserved, no file rewrite). Slight CPU cost — has to hash each
        # file — but at this doc count it's imperceptible.
        cmd = "rsync -ac --delete #{source.shellescape}/ #{dest.shellescape}/ 2>&1"
        output = `#{cmd}`
        unless $?.success?
          raise "Doc sync failed (rsync exit #{$?.exitstatus}): #{output}"
        end

        file_count = Dir.glob(File.join(dest, "**", "*")).count { |p| File.file?(p) }
        log("✓ Synced bundled docs → /site/documentation/roe/ (#{file_count} files)")
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
          "release_date" => Date.today.iso8601
        }

        [
          File.join(RoeSitePaths::ROE_ROOT, "VERSION"),
          File.join(RoeSitePaths::ROE_ROOT, "current", "VERSION")
        ].each do |path|
          existing = File.exist?(path) ? (YAML.load_file(path) || {}) : {}
          File.write(path, existing.merge(data).to_yaml)
          log("✓ Wrote VERSION file: #{path.sub(RoeSitePaths::ROE_ROOT, '')} → #{@version}")
        end
      end

      # Install any gems the new release added or updated. Runs BEFORE
      # build_assets because assets:precompile shells out to
      # `bundle exec rails …`, which forces bundler to resolve the new
      # current/Gemfile.lock — and that resolution raises
      # Bundler::GemNotFound if any locked gem isn't installed yet
      # (typical when a release bumps a dep version or adds a new gem).
      # `bundle install` is a no-op when every locked gem is already
      # present, so this step is cheap for releases that didn't change
      # any deps.
      def install_gems
        current_app = File.join(RoeSitePaths::ROE_ROOT, "current")
        cmd = "cd '#{current_app}' && bundle install 2>&1"
        output = nil

        Bundler.with_original_env do
          output = `#{cmd}`
        end

        unless $?.success?
          raise "bundle install failed (exit #{$?.exitstatus}): #{output}"
        end

        log("✓ Installed/updated gems for new release")
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

        # Invalidate the cached "is there an update available?" result.
        # That cache was populated BEFORE the update with the answer
        # "yes, X is available" — leaving it in place means the next
        # admin page render after the update would still pull that
        # stale entry and show the blue "Update Available" panel
        # alongside the "Restart Roe" message. Clearing it forces a
        # fresh fetch on next render → answers "no, you're current"
        # → correct state.
        RoeUpdater::VersionChecker.clear_cache
        Rails.cache.delete(RoeUpdater::VersionChecker::UPDATE_AVAILABLE_KEY)

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

          # SwitchManager.rollback now propagates failures instead of
          # silently returning false — wrap the rest in the same begin
          # block so a rollback failure lands in the rescue below and
          # gets surfaced to the user verbatim. Also restore root
          # /VERSION here (after the directory swap) so the value the
          # admin UI displays matches the code that current/ is now
          # pointing at.
          SwitchManager.rollback
          restore_root_version

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
          # Surface the actual rollback failure (and its class) in both
          # the log and error_message. Before this, the admin UI would
          # show "Rollback completed" because SwitchManager.rollback
          # rescued internally and returned false — leaving the user
          # convinced everything was clean while current/ was actually
          # half-deleted and current.backup/ was still on disk. Now any
          # exception from rollback (or restore_databases, or
          # cleanup_staging) propagates here with a real message.
          log("CRITICAL: Rollback failed: #{rollback_error.class} - #{rollback_error.message}")
          @status.update!(
            status: "failed",
            error_message: "#{error.message}. Rollback also failed: " \
                          "#{rollback_error.class} - #{rollback_error.message}",
            current_step: "CRITICAL: Manual intervention required"
          )
        end
      end

      # Re-mirror current/VERSION to root /VERSION after a rollback.
      # write_version_files (step 9) wrote the NEW version to root just
      # before the asset-build step that typically fails — leaving root
      # /VERSION pointing at the version we tried to install while
      # current/ has been swapped back to the old code. SwitchManager
      # has already restored current/ from current.backup/ by the time
      # this runs, so current/VERSION holds the correct full YAML
      # (version + release_date + channel + repository) for the
      # rolled-back state. Just copying it to root keeps all the
      # metadata intact — earlier attempts at re-emitting a minimal
      # `{version: X}` hash silently dropped release_date/channel/repo.
      #
      # No-op if current/VERSION doesn't exist for some reason — better
      # to leave whatever's there than overwrite with nothing.
      def restore_root_version
        source = File.join(RoeSitePaths::ROE_ROOT, "current", "VERSION")
        target = File.join(RoeSitePaths::ROE_ROOT, "VERSION")
        return unless File.exist?(source)

        FileUtils.cp(source, target)
      rescue => e
        Rails.logger.warn "Could not restore root VERSION: #{e.message}"
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
