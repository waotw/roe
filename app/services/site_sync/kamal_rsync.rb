require "shellwords"
require "tempfile"
require "yaml"

module SiteSync
  # Kamal-specific transport for site sync. Mirrors the public
  # interface of SiteSync::FlyRsync (push/pull/backup_live with
  # selective + full modes) but uses plain SSH instead of fly's
  # `fly ssh console` wrapper.
  #
  # Reads server, ssh user, and the /site volume mapping from
  # config/deploy.yml so the sync stays in sync with the actual
  # Kamal deploy configuration — no parallel config to maintain.
  #
  # Kamal users need a volume mapping for /data/site in
  # config/deploy.yml so the SSH-side rsync target matches what
  # Roe's container expects. Example:
  #
  #   volumes:
  #     - "/var/lib/roe/site:/data/site"
  #
  # If that mapping is missing, KamalRsync raises a clear error
  # explaining what to add.
  #
  # NOTE: parallel structure to SiteSync::FlyRsync — same shape,
  # same flags, same exclude lists, different transport. They're
  # kept duplicated rather than abstracted into a base class
  # while we're still feeling out the differences in real-world
  # use. Once both are in production for a while and the patterns
  # are stable, extract a shared base.
  class KamalRsync
    class KamalRsyncError < StandardError; end

    # Container path Roe's Dockerfile mounts the site volume at.
    # The HOST path is derived from config/deploy.yml's volume
    # mapping at runtime.
    REMOTE_SITE_CONTAINER_PATH = "/data/site".freeze

    COMMON_EXCLUDES = [
      "--exclude=.sync-state.json",
      "--exclude=.git",
      "--exclude=.sync-backups",
      "--exclude=.DS_Store",
      "--exclude=system/global/.last_deploy.yml",
      # Generated image renditions — a rebuildable cache each side makes
      # on-demand from originals. Syncing them is noise (and needless
      # bandwidth), so keep them out of push/pull/backup like the Ledger.
      "--exclude=media/images/variants/"
    ].freeze

    # system/secrets/ is excluded from PUSH and PULL so dev and prod each
    # keep their own per-install encryption keys (master.key +
    # credentials.yml.enc). BACKUP_EXCLUDES intentionally does NOT
    # exclude it — when pulling a remote /site for backup, you DO want
    # the remote's secrets so that backup is self-sufficient for an
    # emergency restore on the remote environment.
    SECRETS_EXCLUDE = "--exclude=system/secrets/".freeze

    PUSH_EXCLUDES = (COMMON_EXCLUDES + [
      "--exclude=db/production/",
      "--exclude=db/development/.gitkeep",
      SECRETS_EXCLUDE
    ]).freeze

    PULL_EXCLUDES = (COMMON_EXCLUDES + [
      "--exclude=db/development/",
      "--exclude=db/production/.gitkeep",
      SECRETS_EXCLUDE
    ]).freeze

    BACKUP_EXCLUDES = (COMMON_EXCLUDES + [
      "--exclude=db/"
    ]).freeze

    REMOTE_DELETE_BATCH = 50

    # UID/GID of the `rails` user inside the deployed container (per the
    # Dockerfile's `groupadd --gid 1000 rails && useradd --uid 1000 …`).
    # Push direction uses `rsync --chown=#{CONTAINER_OWNERSHIP}` so
    # transferred files land owned by the same uid the Rails process
    # runs under. Without this, plain SSH-as-root rsync drops files
    # into the Kamal host's bind-mount directory as root:root, and
    # because the bind mount preserves host ownership inside the
    # container, Rails (uid 1000) then can't overwrite anything it
    # didn't create itself — admin writes to site.yml, theme CSS,
    # layouts, etc. all silently 500 with EACCES.
    #
    # Paired with --numeric-ids so rsync uses the literal number
    # rather than name-resolving 1000 against the host's /etc/passwd
    # (which may have a different user at that uid).
    CONTAINER_OWNERSHIP = "1000:1000".freeze

    class << self
      # All three public entry points accept an optional `on_progress`
      # callable invoked as rsync transfers files:
      #
      #   on_progress.call(completed: 5, total: 12)
      #
      # Parsed from rsync's `--progress` output (the `to-chk=N/M` token
      # in each per-file summary line). SiteSyncTransferJob uses this
      # to drive the cumulative file counter + progress bar in the
      # admin UI without parsing rsync itself. Mirrors FlyRsync.

      def push_local_to_live!(diff: nil, on_progress: nil)
        diff ? push_selective(diff, on_progress: on_progress) : push_full(on_progress: on_progress)
      end

      def pull_live_to_local!(diff: nil, on_progress: nil)
        diff ? pull_selective(diff, on_progress: on_progress) : pull_full(on_progress: on_progress)
      end

      def backup_live_to_local!(files: nil, on_progress: nil)
        files ? backup_selective(files, on_progress: on_progress) : backup_full(on_progress: on_progress)
      end

      private

      # ─── Push ─────────────────────────────────────────────────────

      def push_selective(diff, on_progress: nil)
        modified = Array(diff[:modified])
        added    = Array(diff[:added])
        deleted  = Array(diff[:deleted])

        files_to_send = modified + added
        if files_to_send.any?
          rsync_files_from(
            source:      "#{RoeSitePaths::SITE_PATH}/",
            dest:        "#{ssh_destination}:#{remote_site_path}",
            files:       files_to_send,
            excludes:    PUSH_EXCLUDES,
            chown:       CONTAINER_OWNERSHIP,
            on_progress: on_progress
          )
        end

        remove_remote_files(deleted) if deleted.any?
      end

      def push_full(on_progress: nil)
        rsync(
          source:      "#{RoeSitePaths::SITE_PATH}/",
          dest:        "#{ssh_destination}:#{remote_site_path}",
          excludes:    PUSH_EXCLUDES,
          delete:      true,
          chown:       CONTAINER_OWNERSHIP,
          on_progress: on_progress
        )
      end

      # ─── Pull ─────────────────────────────────────────────────────

      def pull_selective(diff, on_progress: nil)
        modified = Array(diff[:modified])
        added    = Array(diff[:added])
        deleted  = Array(diff[:deleted])

        files_to_fetch = modified + added
        if files_to_fetch.any?
          rsync_files_from(
            source:      "#{ssh_destination}:#{remote_site_path}",
            dest:        "#{RoeSitePaths::SITE_PATH}/",
            files:       files_to_fetch,
            excludes:    PULL_EXCLUDES,
            on_progress: on_progress
          )
        end

        remove_local_files(deleted) if deleted.any?
      end

      def pull_full(on_progress: nil)
        rsync(
          source:      "#{ssh_destination}:#{remote_site_path}",
          dest:        "#{RoeSitePaths::SITE_PATH}/",
          excludes:    PULL_EXCLUDES,
          delete:      true,
          on_progress: on_progress
        )
      end

      # ─── Backup ───────────────────────────────────────────────────

      def backup_selective(files, on_progress: nil)
        files = Array(files).uniq
        if files.empty?
          Rails.logger.info "[SiteSync::KamalRsync] selective backup: no files in diff, skipping"
          return nil
        end

        backup_dir, backup_root, timestamp = new_backup_dir
        FileUtils.mkdir_p(backup_dir)

        rsync_files_from(
          source:      "#{ssh_destination}:#{remote_site_path}",
          dest:        "#{backup_dir}/",
          files:       files,
          excludes:    BACKUP_EXCLUDES,
          extra_flags: "--ignore-missing-args",
          on_progress: on_progress
        )

        if Dir.empty?(backup_dir)
          Rails.logger.warn "[SiteSync::KamalRsync] selective backup empty for #{files.size} files"
        end

        update_latest_symlink(backup_root, timestamp)
        backup_dir
      end

      def backup_full(on_progress: nil)
        backup_dir, backup_root, timestamp = new_backup_dir

        previous   = previous_backup(backup_root)
        link_dest  = previous ? "--link-dest=#{Shellwords.escape(File.expand_path(previous))}" : ""

        FileUtils.mkdir_p(backup_dir)

        cmd = build_cmd(
          source:   "#{ssh_destination}:#{remote_site_path}",
          dest:     "#{backup_dir}/",
          # Drop -H — /site has no internal hardlinks, and -H makes
          # rsync build a hardlink graph across the whole tree even
          # when there's nothing to track.
          flags:    "-rltzPi #{link_dest}",
          excludes: BACKUP_EXCLUDES
        )

        output, success = run_streaming(cmd, on_progress: on_progress)

        unless success
          FileUtils.rm_rf(backup_dir)
          raise KamalRsyncError, "Live backup failed:\n#{output}"
        end

        if Dir.empty?(backup_dir)
          FileUtils.rm_rf(backup_dir)
          raise KamalRsyncError, "Live backup is empty after rsync — transport likely broken."
        end

        update_latest_symlink(backup_root, timestamp)
        backup_dir
      end

      # ─── Kamal config readers ─────────────────────────────────────

      def kamal_config
        @kamal_config ||= begin
          path = Rails.root.join("config", "deploy.yml")
          unless File.exist?(path)
            raise KamalRsyncError, "config/deploy.yml not found — Kamal deploy isn't configured."
          end
          YAML.load_file(path)
        end
      end

      def host
        @host ||= begin
          servers = kamal_config["servers"]
          host_value = case servers
          when Hash
                         # Kamal supports roles. Use the 'web' role
                         # first (most common), falling back to first
                         # role defined.
                         role = servers["web"] || servers.values.first
                         Array(role).first
          when Array
                         servers.first
          end

          unless host_value && host_value.to_s != "192.168.0.1"
            raise KamalRsyncError, "config/deploy.yml has no real server configured " \
                                   "(found #{host_value.inspect}). Set servers.web to your actual host."
          end
          host_value
        end
      end

      def ssh_user
        kamal_config.dig("ssh", "user") || "root"
      end

      def ssh_destination
        @ssh_destination ||= "#{ssh_user}@#{host}"
      end

      # The HOST path of the /data/site volume — that's where rsync
      # writes since we operate on the host filesystem (the container
      # sees the same content via bind mount).
      def remote_site_path
        @remote_site_path ||= begin
          volumes = Array(kamal_config["volumes"])
          site_volume = volumes.find { |v| v.to_s.split(":").last.to_s.start_with?(REMOTE_SITE_CONTAINER_PATH) }

          unless site_volume
            raise KamalRsyncError, <<~MSG
              config/deploy.yml has no volume mapping for #{REMOTE_SITE_CONTAINER_PATH}.
              Add a volume entry under 'volumes:' like:
                volumes:
                  - "/var/lib/roe/site:#{REMOTE_SITE_CONTAINER_PATH}"
              so site sync knows where on the host filesystem to rsync to.
            MSG
          end

          host_path = site_volume.split(":").first
          host_path.end_with?("/") ? host_path : "#{host_path}/"
        end
      end

      # ─── rsync invocation ────────────────────────────────────────

      def rsync(source:, dest:, excludes:, delete:, chown: nil, on_progress: nil)
        flags = "-rltzPi"
        flags += " --delete" if delete
        flags += " --chown=#{chown} --numeric-ids" if chown
        cmd = build_cmd(source: source, dest: dest, flags: flags, excludes: excludes)
        with_retries(label: "rsync") do
          output, success = run_streaming(cmd, on_progress: on_progress)
          raise KamalRsyncError, "rsync failed:\n#{output}" unless success
          return output
        end
      end

      def rsync_files_from(source:, dest:, files:, excludes: [], extra_flags: "", chown: nil, on_progress: nil)
        files = Array(files).uniq
        return if files.empty?

        list = Tempfile.create([ "site-sync-files", ".txt" ])
        begin
          list.write(files.join("\n"))
          list.close

          flags = "-rltzPi --files-from=#{Shellwords.escape(list.path)} #{extra_flags}".strip
          flags += " --chown=#{chown} --numeric-ids" if chown
          cmd = build_cmd(
            source:   source,
            dest:     dest,
            flags:    flags,
            excludes: excludes
          )

          with_retries(label: "rsync_files_from") do
            output, success = run_streaming(cmd, on_progress: on_progress)
            raise KamalRsyncError, "selective rsync failed:\n#{output}" unless success
            return output
          end
        ensure
          File.unlink(list.path) if list && File.exist?(list.path)
        end
      end

      # Plain ssh as transport — no fly-rsync wrapper. Simpler than
      # FlyRsync's build_cmd because we don't need to cd into Rails.root
      # to use a relative path for -e (the path-with-spaces issue is
      # specific to fly's wrapper).
      def build_cmd(source:, dest:, flags:, excludes:)
        excludes_str = excludes.join(" ")
        "rsync #{flags} #{excludes_str} -e #{Shellwords.escape(ssh_transport)} " \
          "#{Shellwords.escape(source)} #{Shellwords.escape(dest)} 2>&1"
      end

      # The `-e` argument for rsync. Plain "ssh" when no key is pinned
      # in deploy.yml's kamal.ssh.keys (system defaults: ~/.ssh/config,
      # agent identities, etc.). When one IS pinned, lock rsync to that
      # key — IdentitiesOnly=yes stops ssh from offering every other
      # identity first, which would otherwise blow past the server's
      # MaxAuthTries before reaching the right key. Mirrors the same
      # path Kamal itself uses, so `kamal deploy` and Site Sync agree
      # on which identity to present.
      def ssh_transport
        path = Array(kamal_config.dig("ssh", "keys")).first.to_s.strip
        return "ssh" if path.empty?
        "ssh -i #{path} -o IdentitiesOnly=yes"
      end

      def with_retries(label:, max_retries: 2)
        attempts = 0
        begin
          attempts += 1
          yield
        rescue KamalRsyncError => e
          if attempts <= max_retries
            backoff = attempts # 1s, 2s
            Rails.logger.warn "[SiteSync::KamalRsync] #{label}: attempt #{attempts} failed (#{e.message.lines.first&.chomp}); retrying in #{backoff}s"
            sleep backoff
            retry
          else
            raise
          end
        end
      end

      def run(cmd)
        Rails.logger.info "[SiteSync::KamalRsync] #{cmd}"
        output = `#{cmd}`
        [ output, $?.success? ]
      end

      # Streaming variant of `run`. Reads rsync output line-by-line and
      # calls on_progress.call(completed:, total:) when it spots a
      # `to-chk=N/M` token in a per-file progress summary (emitted by
      # `--progress`, which `-P` enables). N = files remaining, M = total
      # files in the transfer — so completed = M - N. Mirrors FlyRsync.
      TO_CHK_RE = /to-chk=(\d+)\/(\d+)/

      def run_streaming(cmd, on_progress: nil)
        Rails.logger.info "[SiteSync::KamalRsync] #{cmd}"
        output = +""
        IO.popen(cmd) do |io|
          io.each_line do |line|
            output << line
            next unless on_progress && line =~ TO_CHK_RE
            remaining = $1.to_i
            total     = $2.to_i
            on_progress.call(completed: total - remaining, total: total)
          end
        end
        [ output, $?.success? ]
      end

      # ─── Remote/local file deletion ──────────────────────────────

      def remove_remote_files(paths)
        return if paths.empty?

        paths.each_slice(REMOTE_DELETE_BATCH) do |chunk|
          remote_paths = chunk.map { |p| File.join(remote_site_path, p) }
          rm_arg = remote_paths.map { |p| Shellwords.escape(p) }.join(" ")
          # Plain ssh — much simpler than fly's machine-id lookup.
          remote_cmd = "rm -f #{rm_arg}"
          cmd = "ssh #{Shellwords.escape(ssh_destination)} #{Shellwords.escape(remote_cmd)} 2>&1"

          output, success = run(cmd)
          raise KamalRsyncError, "remote delete failed:\n#{output}" unless success
        end
      end

      def remove_local_files(paths)
        return if paths.empty?

        site_root = File.expand_path(RoeSitePaths::SITE_PATH)
        paths.each do |p|
          # Defense in depth: refuse paths that try to escape /site.
          next if p.to_s.include?("..") || p.to_s.start_with?("/")

          full = File.expand_path(File.join(RoeSitePaths::SITE_PATH, p))
          next unless full.start_with?(site_root + "/")

          File.delete(full) if File.exist?(full)
        rescue => e
          Rails.logger.warn "[SiteSync::KamalRsync] Could not delete #{p}: #{e.message}"
        end
      end

      # ─── Backup helpers ──────────────────────────────────────────

      def new_backup_dir
        timestamp   = Time.now.strftime("%Y-%m-%d-%H%M%S")
        backup_root = File.join(RoeSitePaths::ROE_ROOT, "site_backups", "production")
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
        latest = File.join(backup_root, "latest")
        FileUtils.rm_f(latest) if File.symlink?(latest) || File.exist?(latest)
        FileUtils.ln_s(timestamp, latest)
      end
    end
  end
end
