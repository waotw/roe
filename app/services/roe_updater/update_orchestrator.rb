require "shellwords"

module RoeUpdater
  class UpdateOrchestrator
    STEPS = [
      { name: "validating",         percent: 5,   description: "Validating update prerequisites" },
      { name: "backing_up_db",      percent: 15,  description: "Creating database backup" },
      { name: "downloading",        percent: 30,  description: "Downloading new version" },
      { name: "checking_ruby",      percent: 35,  description: "Checking Ruby compatibility" },
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
    # current/ is canonical; these are the files mirrored up to ROE_ROOT/.
    # Matches bin/sync-from-site's root-file step. AGENTS.md is intentionally
    # NOT here — it's developer material that rides along in current/ for
    # anyone cloning the repo, and doesn't need to sit at the package root.
    ROOT_SYNC_FILES = %w[roe.sh README.md LICENSE].freeze

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
      def start_update(to_version, status_record, ruby_confirmed: false, resume: false)
        @status = status_record
        @version = to_version
        @ruby_confirmed = ruby_confirmed

        # HARD SAFETY NET — refuse on a developer checkout before ANY
        # destructive step. The controller blocks the web button, but this
        # guards every entry point (rake tasks, a direct PerformUpdateJob
        # enqueue, future callers): nothing can clone a release tag over an
        # active working tree and wipe uncommitted work. See
        # refuse_on_dev_checkout!.
        return if refuse_on_dev_checkout!

        # A fresh run validates, backs up, and downloads. A RESUME (the user
        # just approved the in-browser Ruby install after we paused at
        # checking_ruby) reuses the staging/ clone and DB backup from the
        # first pass, so it skips straight to the Ruby step and continues.
        unless resume
          execute_step(:validating) { validate_prerequisites }
          execute_step(:backing_up_db) { BackupManager.backup_databases(@status) }
          execute_step(:downloading) { Downloader.download_version(@version, @status) }
        end

        # ensure_ruby_available throws :roe_awaiting_ruby when the release
        # pins a Ruby that isn't installed and the user hasn't yet approved
        # installing it. catch() turns that throw into a clean stop: the
        # status is left at "awaiting_ruby", staging/ stays in place, and
        # NOTHING is switched or migrated. The update resumes here (with
        # resume: true, ruby_confirmed: true) once they click Install.
        catch(:roe_awaiting_ruby) do
          execute_step(:checking_ruby) { ensure_ruby_available }
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
        end
      rescue => e
        handle_failure(e)
      end

      private

      # HARD SAFETY NET: refuse to run the updater on a developer checkout of
      # Roe — HEAD on a named git branch — because the version swap clones a
      # release over current/ and would destroy the working tree (and any
      # uncommitted work). A normal user install is a detached release tag
      # and passes straight through, so users update normally. Marks the
      # update failed and returns true so start_update bails before touching
      # anything. Override only with ROE_ALLOW_DEV_UPDATE=1, for a maintainer
      # exercising the updater on a throwaway install — never via the UI.
      def refuse_on_dev_checkout!
        return false unless RoeUpdater::VersionChecker.dev_install?
        return false if ENV["ROE_ALLOW_DEV_UPDATE"] == "1"

        msg = "Update refused: this is a development checkout of Roe (HEAD is on a git branch). " \
              "The in-app updater clones a release over current/ and would destroy your working tree. " \
              "Change versions with git instead."
        log(msg)
        @status.update!(
          status:        "failed",
          current_step:  "Refused — development checkout",
          error_message: msg
        )
        true
      end

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

      # Gate: make sure the Ruby the downloaded release pins is INSTALLED
      # before we switch to it. Runs right after download and BEFORE the
      # swap/migrations, so anything here is a cheap no-op stop — only
      # staging/ exists; the live site is untouched.
      #
      # Availability, not "am I running it": roe.sh boots the app on the
      # exact version in current/.ruby-version, and that only becomes the
      # new version AFTER the swap. So the running Ruby can't be the new
      # one yet — what matters is that the new one is *installed*, so the
      # post-update restart can boot on it. We check for the exact version
      # via the user's manager (mise or rbenv).
      #
      # Three outcomes:
      #   • already installed (or no Ruby change) → return, proceed.
      #   • missing, user hasn't approved an install → pause: set status
      #     "awaiting_ruby" and throw, leaving staging/ intact. The browser
      #     shows an Install / Cancel panel; confirming resumes here.
      #   • missing, user approved (@ruby_confirmed) → install it via mise
      #     (installing mise first if absent), then verify and proceed.
      def ensure_ruby_available
        required = staged_ruby_version
        return if required.nil?
        return if ruby_available?(required)

        unless @ruby_confirmed
          @status.update!(
            status: "awaiting_ruby",
            current_step: "Ruby #{required} required to continue"
          )
          log("⏸  This release needs Ruby #{required}, which isn't installed. " \
              "Waiting for your go-ahead to install it.")
          throw :roe_awaiting_ruby
        end

        install_required_ruby(required)

        return if ruby_available?(required)

        raise "Ruby #{required} still isn't available after the install attempt. " \
              "Install it manually (e.g. `mise use --global ruby@#{required}`) and retry the update."
      end

      # The Ruby version the downloaded release pins (staging/.ruby-version),
      # or nil when the release doesn't pin one.
      def staged_ruby_version
        read_ruby_version(File.join(Downloader::STAGING_PATH, ".ruby-version"))
      end

      # The Ruby version current/ pins AFTER the swap — used to run the
      # post-swap gem/asset builds under the version the app will boot on.
      def current_ruby_version
        read_ruby_version(File.join(RoeSitePaths::ROE_ROOT, "current", ".ruby-version"))
      end

      def read_ruby_version(path)
        return nil unless File.exist?(path)

        version = File.read(path).strip
        version.empty? ? nil : version
      end

      # Is EXACTLY this Ruby installed and resolvable on this machine? roe.sh
      # activates the exact pinned version, so an equal-or-newer running Ruby
      # doesn't help unless the exact version is installed too.
      def ruby_available?(version)
        return true if RUBY_VERSION == version

        Bundler.with_original_env do
          if (mise = mise_bin)
            return true if system("#{mise} where ruby@#{version} > /dev/null 2>&1")
          end
          if command_available?("rbenv")
            installed = `rbenv versions --bare 2>/dev/null`.split("\n").map(&:strip)
            return true if installed.include?(version)
          end
        end
        false
      end

      # Install the pinned Ruby via mise (installing mise itself first if the
      # machine doesn't have it). Streams output into the update log. mise
      # only needs the version INSTALLED — roe.sh's `mise env -C current`
      # resolves it from current/.ruby-version on the next boot, so we don't
      # touch the user's global.
      def install_required_ruby(version)
        ensure_mise!
        mise = mise_bin
        raise "mise isn't available to install Ruby #{version}." unless mise

        configure_mise(mise)

        @status.update!(
          status: "in_progress",
          current_step: "Installing Ruby #{version} (via mise)…",
          progress_percent: 40
        )
        log("→ Installing Ruby #{version} via mise (usually ~30s)…")

        Bundler.with_original_env do
          output = `#{mise} install "ruby@#{version}" 2>&1`
          log(output.to_s.strip) if output.to_s.strip.present?
          raise "mise failed to install Ruby #{version}: #{output}" unless $?.success?
        end
        log("✓ Ruby #{version} installed")
      end

      # Install mise via its official one-line installer when it's missing.
      # The standalone installer drops the binary at ~/.local/bin/mise and
      # needs no sudo. No-op when mise is already present.
      def ensure_mise!
        return if mise_bin

        @status.update!(current_step: "Installing mise…", progress_percent: 38)
        log("→ mise not found — installing it (https://mise.run)…")
        Bundler.with_original_env do
          output = `curl -fsSL https://mise.run | sh 2>&1`
          log(output.to_s.strip) if output.to_s.strip.present?
          raise "Failed to install mise automatically: #{output}" unless $?.success?
        end
        raise "mise install ran but its binary still isn't found." unless mise_bin
        log("✓ mise installed")
      end

      # Locate the mise binary: on PATH first, then the standalone
      # installer's default (~/.local/bin) and the Homebrew locations —
      # mirrors roe.sh's discovery so a mise installed by roe.sh is found
      # here too. Returns the command/path string, or nil if not found.
      def mise_bin
        return "mise" if command_available?("mise")

        [ File.join(Dir.home, ".local/bin/mise"),
          "/opt/homebrew/bin/mise",
          "/usr/local/bin/mise" ].find { |path| File.executable?(path) }
      end

      def command_available?(cmd)
        Bundler.with_original_env { system("command -v #{cmd} > /dev/null 2>&1") }
      end

      # Mirror roe.sh's mise setup so a mise we install (or an existing one)
      # behaves the way roe.sh's restart expects:
      #   • idiomatic_version_file_enable_tools=ruby — modern mise ignores
      #     .ruby-version WITHOUT this, so roe.sh's `mise env -C current`
      #     wouldn't pin the new Ruby and the app would fall through to the
      #     system Ruby on restart.
      #   • ruby.compile=false — install precompiled Ruby (seconds) instead
      #     of a source build (slow, and where the OpenSSL failures live).
      # Idempotent; both `set` calls overwrite to the same value.
      def configure_mise(mise)
        Bundler.with_original_env do
          system("#{mise} settings set idiomatic_version_file_enable_tools ruby > /dev/null 2>&1")
          system("#{mise} settings set ruby.compile false > /dev/null 2>&1")
        end
      end

      # Prefix for the post-swap gem/asset build commands. When the release
      # bumped Ruby, current/.ruby-version now differs from the Ruby THIS
      # (old) process runs — so run bundle/asset builds under the pinned
      # Ruby via mise, ensuring native extensions build for the version the
      # app will actually boot on. Empty (no prefix) when there's no bump or
      # mise isn't available.
      def ruby_target_prefix
        required = current_ruby_version
        return "" if required.nil? || required == RUBY_VERSION

        mise = mise_bin
        mise ? "#{mise} exec \"ruby@#{required}\" -- " : ""
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
        cmd = "cd '#{current_app}' && #{ruby_target_prefix}bundle install 2>&1"
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

        cmd = "cd '#{current_app}' && RAILS_ENV=#{rails_env} #{ruby_target_prefix}bundle exec rails assets:precompile 2>&1"
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
