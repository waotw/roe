require 'shellwords'

module SiteSync
  # rsync-mirror snapshot backups of /site, stored at
  # ROE_ROOT/site_backups/local/<YYYY-MM-DD-HHMMSS>/. Each snapshot
  # is a real, browsable copy of /site; --link-dest hardlinks files
  # that haven't changed since the previous snapshot, so multiple
  # backups of a 2GB site only consume a few MB extra each.
  #
  # Each snapshot writes a small .snapshot_meta.json containing the
  # fingerprint of its contents (size+mtime hash, same scheme as
  # SiteSync::Ledger). The admin UI uses that to mark "currently
  # active" — the backup whose fingerprint matches /site's current
  # state. Restoring a different backup, or editing /site, naturally
  # transfers active status.
  #
  # On-disk layout matches the production-side `rake site:backup`
  # task (which writes to site_backups/production/) so the two are
  # consistent and either can be restored from with the same tools.
  class BackupManager
    class BackupError < StandardError; end

    BACKUP_RETENTION = 15
    BACKUP_ROOT      = File.join(RoeSitePaths::ROE_ROOT, 'site_backups', 'local')

    # Per-snapshot metadata file (fingerprint, etc.) lives at the
    # root of the snapshot dir. Excluded from rsync in both directions
    # so it never escapes into /site on restore.
    SNAPSHOT_META_FILENAME = '.snapshot_meta.json'

    # rsync excludes mirror SiteSync::Ledger's exclusion lists, plus
    # the snapshot meta file. Paths are relative to /site (the rsync
    # source root) — leading "/" pins them to that root.
    RSYNC_EXCLUDES = [
      '/db',                        # has its own backup system
      '/.git',                      # user's optional /site git repo
      '/.sync-state.json',          # the ledger
      '/.sync-backups',             # legacy/defensive
      '/media/images/variants',     # generated files, can be rebuilt from originals
      '/' + SNAPSHOT_META_FILENAME, # never let this escape into /site
      '.DS_Store'                   # match anywhere
    ].freeze

    # Match the `YYYY-MM-DD-HHMMSS` directory naming used by both
    # this manager and the rake site:backup task. Keeps `latest`,
    # `_before_restore` (legacy), and any stray dot-files out of
    # the listing.
    SNAPSHOT_NAME_RE = /\A\d{4}-\d{2}-\d{2}-\d{6}\z/.freeze

    class << self
      # Snapshot /site into BACKUP_ROOT/<timestamp>/ via rsync with
      # --link-dest pointed at the previous snapshot for hardlink
      # dedup. Writes a .snapshot_meta.json with the fingerprint of
      # the captured state. Returns the absolute snapshot path.
      def create
        ensure_site_present!
        FileUtils.mkdir_p(BACKUP_ROOT)

        timestamp  = Time.now.strftime("%Y-%m-%d-%H%M%S")
        backup_dir = File.join(BACKUP_ROOT, timestamp)

        link_dest_arg = previous_snapshot ? "--link-dest=#{Shellwords.escape(previous_snapshot)}" : ""
        excludes_arg  = RSYNC_EXCLUDES.map { |e| "--exclude=#{Shellwords.escape(e)}" }.join(' ')

        FileUtils.mkdir_p(backup_dir)

        # -a : archive (perms, times, symlinks, recursive)
        # -H : preserve hardlinks within the source tree
        # Trailing slash on source so we copy contents-of-site, not
        # the site/ wrapper itself.
        cmd = "rsync -aH #{link_dest_arg} #{excludes_arg} " \
              "#{Shellwords.escape("#{RoeSitePaths::SITE_PATH}/")} " \
              "#{Shellwords.escape("#{backup_dir}/")} 2>&1"

        output = `#{cmd}`

        unless $?.success?
          FileUtils.rm_rf(backup_dir)
          raise BackupError, "Site backup failed: #{output}"
        end

        # Belt-and-suspenders: rsync occasionally exits 0 with nothing
        # transferred under broken transports. An empty dir is never
        # a successful backup — refuse to advance state.
        if Dir.empty?(backup_dir)
          FileUtils.rm_rf(backup_dir)
          raise BackupError, "Backup dir is empty after rsync — nothing was transferred."
        end

        write_snapshot_meta(backup_dir)
        update_latest_symlink(timestamp)
        prune!

        # Intentionally NOT writing the sync ledger here. Creating a
        # backup is about "I have a restorable snapshot of this state"
        # — it says nothing about whether that state has been synced to
        # the peer. Conflating the two used to claim drift was resolved
        # by taking a backup, which broke cross-env in-sync detection
        # (banner read "no drift" while peer was on different content).

        backup_dir
      end

      # Snapshots newest first. Each entry includes:
      #   - name, path, size, created_at
      #   - fingerprint (nil for legacy snapshots without meta)
      #   - active (true if fingerprint matches /site's current state)
      #
      # Filtering by SNAPSHOT_NAME_RE keeps `latest`, the legacy
      # `_before_restore/` subdir, `.DS_Store`, etc. out of the list.
      def list
        return [] unless Dir.exist?(BACKUP_ROOT)

        current_fp = current_site_fingerprint

        Dir.children(BACKUP_ROOT)
           .select { |name| name =~ SNAPSHOT_NAME_RE }
           .map    { |name| describe(File.join(BACKUP_ROOT, name), current_fp) }
           .compact
           .sort_by { |b| -b[:created_at].to_i }
      end

      # Production-side snapshots (created by `rake site:backup`,
      # which pulls from fly via fly-rsync). Read-only here — the
      # rake task owns lifecycle.
      def list_production
        prod_root = File.join(RoeSitePaths::ROE_ROOT, 'site_backups', 'production')
        return [] unless Dir.exist?(prod_root)

        Dir.children(prod_root)
           .select { |name| name =~ SNAPSHOT_NAME_RE }
           .map    { |name| describe(File.join(prod_root, name), nil) }
           .compact
           .sort_by { |b| -b[:created_at].to_i }
      end

      # Restore /site from a local snapshot. Always takes a fresh
      # snapshot of the current state first (which itself becomes a
      # regular entry in the backup list — undoing is just restoring
      # from that one). Returns metadata about the operation.
      def restore(snapshot_name)
        snapshot_path = resolve_snapshot_path(snapshot_name)
        ensure_site_present!

        # The pre-restore snapshot becomes a regular backup entry.
        # No special _before_restore subdir — keeping things uniform
        # means the user just sees one chronological list.
        safety_path = create

        excludes_arg = RSYNC_EXCLUDES.map { |e| "--exclude=#{Shellwords.escape(e)}" }.join(' ')

        # --delete so files removed since the backup actually disappear
        # on restore. Without it, restoring an "older" state would
        # only roll BACK modifications, not deletions — restoring
        # would leave any post-backup additions lying around.
        #
        # Excludes are passed again so we don't accidentally delete
        # /site/db, /site/.git, etc. on the restore side. The backup
        # doesn't contain those, so without the excludes rsync would
        # treat them as "missing from source" and delete them.
        cmd = "rsync -aH --delete #{excludes_arg} " \
              "#{Shellwords.escape("#{snapshot_path}/")} " \
              "#{Shellwords.escape("#{RoeSitePaths::SITE_PATH}/")} 2>&1"

        output = `#{cmd}`

        unless $?.success?
          raise BackupError, "rsync failed during restore: #{output}. Pre-restore snapshot is at #{safety_path}"
        end

        # Intentionally NOT writing the sync ledger here. Restoring
        # from a local snapshot doesn't change anything on the peer —
        # so claiming sync is no longer accurate. The cross-env
        # exchange will report drift correctly on its own; if the
        # restored state happens to match the peer, self-heal will
        # rewrite the ledger automatically.
        Rails.cache.delete("site_sync:current_fingerprint")
        SiteSync::Checker.clear_cache

        {
          safety_path:  safety_path,
          file_count:   count_files(snapshot_path),
          restored_at:  Time.current
        }
      end

      def prune!
        snapshots = list
        return if snapshots.size <= BACKUP_RETENTION

        snapshots[BACKUP_RETENTION..].each do |s|
          FileUtils.rm_rf(s[:path])
          Rails.logger.info "[SiteSync::BackupManager] Pruned old snapshot: #{s[:name]}"
        end
      end

      private

      def ensure_site_present!
        return if Dir.exist?(RoeSitePaths::SITE_PATH)
        raise BackupError, "Site directory not found: #{RoeSitePaths::SITE_PATH}"
      end

      def previous_snapshot
        snapshots = Dir.glob(File.join(BACKUP_ROOT, "20*"))
                       .select { |d| File.directory?(d) && !File.symlink?(d) }
        snapshots.reject! { |d| Dir.empty?(d) rescue true }
        snapshots.sort.last
      end

      def update_latest_symlink(timestamp)
        latest = File.join(BACKUP_ROOT, 'latest')
        FileUtils.rm_f(latest) if File.symlink?(latest) || File.exist?(latest)
        FileUtils.ln_s(timestamp, latest)
      end

      def write_snapshot_meta(snapshot_dir)
        meta = {
          'fingerprint' => SiteSync::Ledger.fingerprint_for(snapshot_dir),
          'created_at'  => Time.now.utc.iso8601
        }
        File.write(File.join(snapshot_dir, SNAPSHOT_META_FILENAME), JSON.pretty_generate(meta))
      end

      def read_snapshot_fingerprint(snapshot_dir)
        meta_path = File.join(snapshot_dir, SNAPSHOT_META_FILENAME)
        return nil unless File.exist?(meta_path)
        JSON.parse(File.read(meta_path))['fingerprint']
      rescue JSON::ParserError, Errno::ENOENT
        nil
      end

      # Cached so a page render listing 15 backups doesn't trigger
      # 15 separate /site walks. 30s TTL matches SiteSync::Checker's
      # cadence. Bust on restore (controller does this).
      def current_site_fingerprint
        Rails.cache.fetch("site_sync:current_fingerprint", expires_in: 30.seconds) do
          SiteSync::Ledger.fingerprint_for(RoeSitePaths::SITE_PATH)
        end
      rescue => e
        Rails.logger.error "[SiteSync::BackupManager] fingerprint_for failed: #{e.message}"
        nil
      end

      def resolve_snapshot_path(name)
        path = File.expand_path(File.join(BACKUP_ROOT, name))

        # Defense in depth: even though this is admin-gated, refuse
        # any name that escapes BACKUP_ROOT (e.g. "../../etc/...").
        unless path.start_with?(File.expand_path(BACKUP_ROOT) + '/')
          raise BackupError, "Invalid snapshot name: #{name}"
        end

        unless Dir.exist?(path)
          raise BackupError, "Snapshot not found: #{name}"
        end

        path
      end

      def describe(path, current_fingerprint)
        return nil unless Dir.exist?(path)
        stat = File.stat(path)
        fp   = read_snapshot_fingerprint(path)

        {
          name:        File.basename(path),
          path:        path,
          size:        du_bytes(path),
          created_at:  stat.mtime,
          fingerprint: fp,
          active:      !current_fingerprint.nil? && !fp.nil? && fp == current_fingerprint
        }
      end

      def du_bytes(path)
        # `du -sk` returns size in 1024-byte blocks. For hardlinked
        # snapshots this is "apparent size" (the size files would
        # have if independently stored), not "incremental disk used"
        # — that's what we want for UI display since users think in
        # terms of "this snapshot represents X of content."
        kb = `du -sk #{Shellwords.escape(path)} 2>/dev/null`.split.first
        kb ? kb.to_i * 1024 : nil
      rescue
        nil
      end

      def count_files(path)
        Dir.glob(File.join(path, '**', '*'), File::FNM_DOTMATCH).count do |f|
          File.file?(f) && !File.symlink?(f)
        end
      end
    end
  end
end
