require 'shellwords'
require 'json'
require 'tempfile'

module SiteSync
  # Fly-specific transport for site sync operations. Wraps the
  # existing bin/fly-rsync bash script (which routes rsync over
  # `fly ssh console`) into class-method calls that the admin
  # background jobs can invoke directly.
  #
  # Two modes per direction:
  #
  #   - **Selective** (preferred): caller supplies a diff (modified/
  #     added/deleted) computed locally from the ledger. We rsync
  #     only those files via --files-from, and handle deletes via a
  #     batched `ssh rm -f`. Skips the full-tree walk on both sides
  #     entirely. Much faster when only a handful of files changed
  #     — which is the normal workflow.
  #
  #   - **Full** (fallback): full-tree rsync with --delete. Used
  #     when there's no reliable diff (e.g. peer sent truncated
  #     drift or no drift info at all). Same shape as the existing
  #     rake site:* tasks.
  #
  # When Kamal lands, expect a parallel `SiteSync::KamalRsync` and
  # a thin selector based on deploy target. Don't try to abstract
  # before then — fly's machines API + ssh wrapper has genuinely
  # different shape from Kamal's plain ssh + Docker.
  class FlyRsync
    class FlyRsyncError < StandardError; end

    DEFAULT_APP_NAME  = 'roe'.freeze
    REMOTE_SITE_PATH  = '/data/site/'.freeze

    # Excludes that apply in both directions. These should mirror
    # SiteSync::Ledger's EXCLUDED_DIRS/EXCLUDED_FILES so that the
    # set of files rsync transfers matches the set the ledger
    # tracks — otherwise rsync would touch files the ledger
    # ignores (or vice versa), creating phantom drift.
    #
    # `.sync-state.json` is the critical one: each environment
    # writes its OWN ledger. If dev's ledger gets pushed to prod,
    # prod's drift detection breaks (prod sees dev's ledger as if
    # it were its own — every file with a different mtime is
    # "modified"). Plus, rsync via `fly ssh console` runs as root,
    # so the transferred file ends up owned by root — and the
    # Rails app on prod runs as non-root, so it can't rewrite the
    # ledger afterwards (Errno::EACCES → refresh_peer_ledger 500s).
    COMMON_EXCLUDES = [
      '--exclude=.sync-state.json',
      '--exclude=.git',
      '--exclude=.sync-backups',
      '--exclude=.DS_Store',
      '--exclude=system/global/.last_deploy.yml'
    ].freeze

    # Push (dev → prod): protect prod's DB from being clobbered
    # by dev's. Same DB-protection rules as the rake site:* tasks.
    PUSH_EXCLUDES = (COMMON_EXCLUDES + [
      '--exclude=db/production/',
      '--exclude=db/development/.gitkeep'
    ]).freeze

    # Pull (prod → dev): protect dev's DB from being clobbered
    # by prod's. Mirror image of PUSH_EXCLUDES.
    PULL_EXCLUDES = (COMMON_EXCLUDES + [
      '--exclude=db/development/',
      '--exclude=db/production/.gitkeep'
    ]).freeze

    # Backup (live → local snapshot): exclude the entire DB tree
    # since DBs have their own backup system.
    BACKUP_EXCLUDES = (COMMON_EXCLUDES + [
      '--exclude=db/'
    ]).freeze

    # When deleting many files via fly ssh console, batch them so
    # a single SSH session covers a whole chunk (each fly ssh call
    # has 5–15 seconds of overhead).
    REMOTE_DELETE_BATCH = 50

    class << self
      # Push local /site to live. If `diff` is given, only the listed
      # modified/added files are rsync'd (via --files-from) and the
      # listed deleted files are removed remotely via ssh rm. If
      # `diff` is nil, falls back to a full-tree `rsync --delete`.
      def push_local_to_live!(diff: nil)
        if diff
          push_selective(diff)
        else
          push_full
        end
      end

      # Pull live /site over local. Same selective/full split as push.
      def pull_live_to_local!(diff: nil)
        if diff
          pull_selective(diff)
        else
          pull_full
        end
      end

      # Snapshot live → local under site_backups/production/<ts>/.
      # If `files` is given, only those are pulled into the snapshot;
      # callers typically pass the diff's modified+deleted (the files
      # about to be overwritten/removed by a push) so the snapshot
      # captures exactly what's at risk. If nil, full backup.
      def backup_live_to_local!(files: nil)
        if files
          backup_selective(files)
        else
          backup_full
        end
      end

      private

      # ─── Push ─────────────────────────────────────────────────────

      def push_selective(diff)
        modified = Array(diff[:modified])
        added    = Array(diff[:added])
        deleted  = Array(diff[:deleted])

        files_to_send = modified + added
        if files_to_send.any?
          rsync_files_from(
            source:   "#{RoeSitePaths::SITE_PATH}/",
            dest:     "#{machine_id}:#{REMOTE_SITE_PATH}",
            files:    files_to_send,
            excludes: PUSH_EXCLUDES
          )
        end

        remove_remote_files(deleted) if deleted.any?
      end

      def push_full
        rsync(
          source:   "#{RoeSitePaths::SITE_PATH}/",
          dest:     "#{machine_id}:#{REMOTE_SITE_PATH}",
          excludes: PUSH_EXCLUDES,
          delete:   true
        )
      end

      # ─── Pull ─────────────────────────────────────────────────────

      def pull_selective(diff)
        modified = Array(diff[:modified])
        added    = Array(diff[:added])
        deleted  = Array(diff[:deleted])

        files_to_fetch = modified + added
        if files_to_fetch.any?
          rsync_files_from(
            source:   "#{machine_id}:#{REMOTE_SITE_PATH}",
            dest:     "#{RoeSitePaths::SITE_PATH}/",
            files:    files_to_fetch,
            excludes: PULL_EXCLUDES
          )
        end

        remove_local_files(deleted) if deleted.any?
      end

      def pull_full
        rsync(
          source:   "#{machine_id}:#{REMOTE_SITE_PATH}",
          dest:     "#{RoeSitePaths::SITE_PATH}/",
          excludes: PULL_EXCLUDES,
          delete:   true
        )
      end

      # ─── Backup ───────────────────────────────────────────────────

      def backup_selective(files)
        files = Array(files).uniq
        if files.empty?
          Rails.logger.info "[SiteSync::FlyRsync] selective backup: no files in diff, skipping"
          return nil
        end

        backup_dir, backup_root, timestamp = new_backup_dir
        FileUtils.mkdir_p(backup_dir)

        rsync_files_from(
          source:      "#{machine_id}:#{REMOTE_SITE_PATH}",
          dest:        "#{backup_dir}/",
          files:       files,
          excludes:    BACKUP_EXCLUDES,
          extra_flags: "--ignore-missing-args"
        )

        if Dir.empty?(backup_dir)
          # Could happen if every listed file is missing on prod
          # (e.g. local-deleted things that prod also doesn't have).
          # Still record the timestamp so retention/list semantics
          # don't get weird, but don't claim a useful backup exists.
          Rails.logger.warn "[SiteSync::FlyRsync] selective backup empty for #{files.size} files"
        end

        update_latest_symlink(backup_root, timestamp)
        backup_dir
      end

      def backup_full
        backup_dir, backup_root, timestamp = new_backup_dir

        previous   = previous_backup(backup_root)
        link_dest  = previous ? "--link-dest=#{Shellwords.escape(File.expand_path(previous))}" : ""

        FileUtils.mkdir_p(backup_dir)

        cmd = build_cmd(
          source:   "#{machine_id}:#{REMOTE_SITE_PATH}",
          dest:     "#{backup_dir}/",
          # Drop -H — /site has no internal hardlinks, and -H makes
          # rsync build a hardlink graph across the whole tree even
          # when there's nothing to track. Major slowdown over fly
          # ssh console.
          flags:    "-rltzPi #{link_dest}",
          excludes: BACKUP_EXCLUDES
        )

        output, success = run(cmd)

        unless success
          FileUtils.rm_rf(backup_dir)
          raise FlyRsyncError, "Live backup failed:\n#{output}"
        end

        if Dir.empty?(backup_dir)
          FileUtils.rm_rf(backup_dir)
          raise FlyRsyncError, "Live backup is empty after rsync — fly-rsync transport likely broken."
        end

        update_latest_symlink(backup_root, timestamp)
        backup_dir
      end

      # ─── Common helpers ───────────────────────────────────────────

      def app_name
        ENV['FLY_APP_NAME'] || DEFAULT_APP_NAME
      end

      # Cached for the lifetime of the process — machine ID is stable
      # for an app and looking it up shells out to fly CLI, which adds
      # 1-2 seconds. Not memoized across requests since this runs in
      # a job.
      def machine_id
        @machine_id ||= begin
          output = `fly machine list --json -a #{Shellwords.escape(app_name)} 2>&1`
          unless $?.success?
            raise FlyRsyncError, "Could not list fly machines for app '#{app_name}':\n#{output}"
          end
          machines = JSON.parse(output) rescue []
          machine = machines.first
          unless machine && machine['id']
            raise FlyRsyncError, "No fly machines found for app '#{app_name}'."
          end
          machine['id']
        end
      end

      def rsync(source:, dest:, excludes:, delete:)
        flags = "-rltzPi"
        flags += " --delete" if delete
        cmd = build_cmd(source: source, dest: dest, flags: flags, excludes: excludes)
        with_retries(label: "rsync") do
          output, success = run(cmd)
          raise FlyRsyncError, "rsync failed:\n#{output}" unless success
          return output
        end
      end

      # rsync invocation that transfers ONLY the listed files (paths
      # relative to the source root). Skips the full-tree walk on
      # both sides — for a small diff this is dramatically faster
      # than vanilla rsync over fly ssh console.
      def rsync_files_from(source:, dest:, files:, excludes: [], extra_flags: "")
        files = Array(files).uniq
        return if files.empty?

        list = Tempfile.create([ 'site-sync-files', '.txt' ])
        begin
          list.write(files.join("\n"))
          list.close

          flags = "-rltzPi --files-from=#{Shellwords.escape(list.path)} #{extra_flags}".strip
          cmd = build_cmd(
            source:   source,
            dest:     dest,
            flags:    flags,
            excludes: excludes
          )

          with_retries(label: "rsync_files_from") do
            output, success = run(cmd)
            raise FlyRsyncError, "selective rsync failed:\n#{output}" unless success
            return output
          end
        ensure
          File.unlink(list.path) if list && File.exist?(list.path)
        end
      end

      # Generic retry-with-backoff. Yields once + up to `max_retries`
      # additional times on failure. Used to absorb transient fly ssh
      # console hiccups (broken pipes, momentary network blips). rsync
      # itself is idempotent on retry — files already transferred will
      # be skipped via mtime+size comparison.
      def with_retries(label:, max_retries: 2)
        attempts = 0
        begin
          attempts += 1
          yield
        rescue FlyRsyncError => e
          if attempts <= max_retries
            backoff = attempts # 1s, 2s
            Rails.logger.warn "[SiteSync::FlyRsync] #{label}: attempt #{attempts} failed (#{e.message.lines.first&.chomp}); retrying in #{backoff}s"
            sleep backoff
            retry
          else
            raise
          end
        end
      end

      def build_cmd(source:, dest:, flags:, excludes:)
        excludes_str = excludes.join(' ')
        # cd into Rails.root so we can use a relative path for the
        # -e argument. rsync re-tokenizes the -e value on whitespace
        # (so it can support things like `-e "ssh -p 2222"`), which
        # means an absolute path containing spaces gets split into
        # garbage. The existing `rake site:backup` works because it
        # uses `./bin/fly-rsync` — same trick here.
        #
        # Source/dest paths are passed as their own argv tokens and
        # rsync does not re-parse them, so Shellwords.escape on those
        # is sufficient.
        "cd #{Shellwords.escape(Rails.root.to_s)} && " \
          "rsync #{flags} #{excludes_str} -e ./bin/fly-rsync " \
          "#{Shellwords.escape(source)} #{Shellwords.escape(dest)} 2>&1"
      end

      def run(cmd)
        Rails.logger.info "[SiteSync::FlyRsync] #{cmd}"
        output = `#{cmd}`
        [ output, $?.success? ]
      end

      # Batched ssh rm. Each fly ssh console call has ~5–15s of
      # overhead, so we group deletions to amortize.
      def remove_remote_files(paths)
        return if paths.empty?

        paths.each_slice(REMOTE_DELETE_BATCH) do |chunk|
          remote_paths = chunk.map { |p| File.join(REMOTE_SITE_PATH, p) }
          rm_arg = remote_paths.map { |p| Shellwords.escape(p) }.join(' ')
          # rm -f: don't error on already-missing files.
          remote_cmd = "rm -f #{rm_arg}"
          cmd = "fly ssh console --quiet --machine #{Shellwords.escape(machine_id)} " \
                "-C #{Shellwords.escape(remote_cmd)} 2>&1"

          output, success = run(cmd)
          raise FlyRsyncError, "remote delete failed:\n#{output}" unless success
        end
      end

      def remove_local_files(paths)
        return if paths.empty?

        site_root = File.expand_path(RoeSitePaths::SITE_PATH)
        paths.each do |p|
          # Defense in depth: refuse paths that try to escape /site.
          next if p.to_s.include?('..') || p.to_s.start_with?('/')

          full = File.expand_path(File.join(RoeSitePaths::SITE_PATH, p))
          next unless full.start_with?(site_root + '/')

          File.delete(full) if File.exist?(full)
        rescue => e
          Rails.logger.warn "[SiteSync::FlyRsync] Could not delete #{p}: #{e.message}"
        end
      end

      def new_backup_dir
        timestamp   = Time.now.strftime("%Y-%m-%d-%H%M%S")
        backup_root = File.join(RoeSitePaths::ROE_ROOT, 'site_backups', 'production')
        FileUtils.mkdir_p(backup_root)
        backup_dir  = File.join(backup_root, timestamp)
        [ backup_dir, backup_root, timestamp ]
      end

      def previous_backup(backup_root)
        snapshots = Dir.glob(File.join(backup_root, "20*"))
                       .select { |d| File.directory?(d) && !File.symlink?(d) }
        snapshots.reject! { |d| Dir.empty?(d) rescue true }
        snapshots.sort.last
      end

      def update_latest_symlink(backup_root, timestamp)
        latest = File.join(backup_root, 'latest')
        FileUtils.rm_f(latest) if File.symlink?(latest) || File.exist?(latest)
        FileUtils.ln_s(timestamp, latest)
      end
    end
  end
end
