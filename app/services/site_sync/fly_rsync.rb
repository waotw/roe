require 'shellwords'
require 'json'

module SiteSync
  # Fly-specific transport for site sync operations. Wraps the
  # existing bin/fly-rsync bash script (which routes rsync over
  # `fly ssh console`) into class-method calls that the admin
  # background jobs can invoke directly.
  #
  # Mirrors what `rake site:backup` / `rake site:push` do
  # interactively, minus the prompts and STDOUT decoration. The
  # rake tasks remain available for terminal use; this service is
  # purely for the admin-UI sync flow.
  #
  # When Kamal lands, expect a parallel `SiteSync::KamalRsync` (or
  # similar) and a thin selector based on deploy target. Don't try
  # to abstract before then — fly's machines API + ssh wrapper has
  # genuinely different shape from Kamal's plain ssh + Docker.
  class FlyRsync
    class FlyRsyncError < StandardError; end

    DEFAULT_APP_NAME  = 'roe'.freeze
    REMOTE_SITE_PATH  = '/data/site/'.freeze

    # Same exclude patterns the rake tasks use — protect the
    # per-environment DB folders so a push doesn't clobber prod's
    # SQLite with dev's, or vice versa.
    PUSH_EXCLUDES = [
      '--exclude=db/production/',
      '--exclude=db/development/.gitkeep'
    ].freeze

    PULL_EXCLUDES = [
      '--exclude=db/development/',
      '--exclude=db/production/.gitkeep'
    ].freeze

    class << self
      # Push local /site to the live machine. With --delete so the
      # two sides truly match after the operation. Caller should
      # back up live first via `backup_live_to_local!`.
      def push_local_to_live!
        rsync(
          source:   "#{RoeSitePaths::SITE_PATH}/",
          dest:     "#{machine_id}:#{REMOTE_SITE_PATH}",
          excludes: PUSH_EXCLUDES,
          delete:   true
        )
      end

      # Pull live /site to local. With --delete so local matches
      # live exactly. Caller should back up local first via
      # SiteSync::BackupManager.create.
      def pull_live_to_local!
        rsync(
          source:   "#{machine_id}:#{REMOTE_SITE_PATH}",
          dest:     "#{RoeSitePaths::SITE_PATH}/",
          excludes: PULL_EXCLUDES,
          delete:   true
        )
      end

      # Hardlinked snapshot of live's /site under
      # site_backups/production/<timestamp>/. Same on-disk shape
      # as `rake site:backup`.
      def backup_live_to_local!
        timestamp   = Time.now.strftime("%Y-%m-%d-%H%M%S")
        backup_root = File.join(RoeSitePaths::ROE_ROOT, 'site_backups', 'production')
        FileUtils.mkdir_p(backup_root)
        backup_dir  = File.join(backup_root, timestamp)

        previous   = previous_backup(backup_root)
        link_dest  = previous ? "--link-dest=#{Shellwords.escape(File.expand_path(previous))}" : ""

        FileUtils.mkdir_p(backup_dir)

        cmd = build_cmd(
          source:   "#{machine_id}:#{REMOTE_SITE_PATH}",
          dest:     "#{backup_dir}/",
          flags:    "-aHP #{link_dest}",
          excludes: []
        )

        output, success = run(cmd)

        unless success
          FileUtils.rm_rf(backup_dir)
          raise FlyRsyncError, "Live backup failed:\n#{output}"
        end

        # Same belt-and-suspenders the rake task uses: an empty dir
        # after a "successful" rsync usually means the transport
        # broke silently — refuse to advance state.
        if Dir.empty?(backup_dir)
          FileUtils.rm_rf(backup_dir)
          raise FlyRsyncError, "Live backup is empty after rsync — fly-rsync transport likely broken."
        end

        update_latest_symlink(backup_root, timestamp)
        backup_dir
      end

      private

      def app_name
        ENV['FLY_APP_NAME'] || DEFAULT_APP_NAME
      end

      # Cached for the lifetime of the process — machine ID is
      # stable for an app and looking it up shells out to fly CLI,
      # which adds 1-2 seconds. Not memoized across requests since
      # this runs in a job.
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
        output, success = run(cmd)
        raise FlyRsyncError, "rsync failed:\n#{output}" unless success
        output
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
