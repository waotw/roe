require "shellwords"
require "tmpdir"

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
    BACKUP_ROOT      = File.join(RoeSitePaths::ROE_ROOT, "site_backups", "local")

    # Per-snapshot metadata file (fingerprint, etc.) lives at the
    # root of the snapshot dir. Excluded from rsync in both directions
    # so it never escapes into /site on restore.
    SNAPSHOT_META_FILENAME = ".snapshot_meta.json"

    # rsync excludes mirror SiteSync::Ledger's exclusion lists, plus
    # the snapshot meta file. Paths are relative to /site (the rsync
    # source root) — leading "/" pins them to that root.
    RSYNC_EXCLUDES = [
      "/db",                        # has its own backup system
      "/.git",                      # user's optional /site git repo
      "/.sync-state.json",          # the ledger
      "/.sync-backups",             # legacy/defensive
      "/media/images/variants",     # generated files, can be rebuilt from originals
      "/" + SNAPSHOT_META_FILENAME, # never let this escape into /site
      ".DS_Store"                   # match anywhere
    ].freeze

    # Match the `YYYY-MM-DD-HHMMSS` directory naming used by both
    # this manager and the rake site:backup task. Keeps `latest`,
    # `_before_restore` (legacy), and any stray dot-files out of
    # the listing.
    SNAPSHOT_NAME_RE = /\A\d{4}-\d{2}-\d{2}-\d{6}\z/.freeze

    # Auxiliary SQLite files we never carry in a backup — transient and
    # regenerated at boot. Only the primary DB (member/store data) is
    # snapshotted and encrypted.
    TRANSIENT_DB_BASENAMES = %w[cache.sqlite3 queue.sqlite3 cable.sqlite3].freeze

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
        excludes_arg  = RSYNC_EXCLUDES.map { |e| "--exclude=#{Shellwords.escape(e)}" }.join(" ")

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

        # rsync excluded /db above. Fold in the encrypted DB blob if one is
        # already present in /site (staged server-side and synced down, or
        # staged locally). We never ENCRYPT here: a same-machine snapshot has
        # the plaintext DB sitting right beside it, so encrypting adds no
        # protection and would force a passphrase to roll back. Encryption
        # happens on the host, before the blob is pulled off-box.
        include_encrypted_db_in(backup_dir)

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
        prod_root = File.join(RoeSitePaths::ROE_ROOT, "site_backups", "production")
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

        excludes_arg = RSYNC_EXCLUDES.map { |e| "--exclude=#{Shellwords.escape(e)}" }.join(" ")

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

      # ── Encrypted database restore ──────────────────────────────────────
      #
      # Decrypt the DB stored inside a snapshot back into place. This is a
      # SEPARATE, explicit step from `restore` (which handles files and
      # deliberately leaves /db alone): it needs the passphrase and it
      # overwrites the live SQLite file. Run it with the app stopped, or
      # restart afterwards — swapping the DB file under a live connection
      # is unsafe.
      #
      # `dest` defaults to the current environment's primary DB. Returns the
      # destination path. Raises BackupError on a wrong passphrase, a corrupt
      # blob, or a snapshot with no encrypted DB.
      def restore_db(snapshot_name, passphrase, dest: nil)
        snapshot_path = resolve_snapshot_path(snapshot_name)
        enc = encrypted_db_in(snapshot_path)
        raise BackupError, "This backup has no encrypted database." if enc.nil?

        # Verify before touching `dest` so a wrong passphrase fails cleanly
        # without disturbing the DB that's already there.
        unless SiteSync::BackupCrypto.verify(enc, passphrase.to_s)
          raise BackupError, "Wrong passphrase for this backup's database (or the file is corrupt)."
        end

        dest ||= primary_db_path
        raise BackupError, "Could not resolve destination database path." if dest.blank?

        SiteSync::BackupCrypto.decrypt_file(enc, dest, passphrase.to_s)

        # The decrypted copy is a clean, checkpointed DB (see VACUUM INTO on
        # the encrypt side). Drop any stale WAL/shm sidecars left by the DB
        # that used to live here, so SQLite can't replay an old log over it.
        [ "#{dest}-wal", "#{dest}-shm" ].each { |f| FileUtils.rm_f(f) }

        Rails.logger.info "[SiteSync::BackupManager] Restored database from #{snapshot_name} → #{dest}"
        dest
      end

      # Stage an encrypted copy of the live primary DB *inside /site*, at
      # <db>.enc, so the normal sync fileset can carry it off-box. Runs on the
      # host that owns the data (production), right before it serves a pull:
      # the plaintext DB never crosses the wire — only this ciphertext blob.
      # A consistent copy is taken via VACUUM INTO first. No-op (returns nil)
      # when no passphrase is set. Returns the blob path.
      def stage_encrypted_db!(passphrase = nil)
        passphrase ||= backup_passphrase
        return nil if passphrase.blank?

        src = primary_db_path
        return nil unless src && File.file?(src)

        dest = "#{src}.enc"
        with_consistent_db_copy(src) do |copy|
          SiteSync::BackupCrypto.encrypt_file(copy, dest, passphrase)
        end
        Rails.logger.info "[SiteSync::BackupManager] Staged encrypted DB: #{File.basename(dest)}"
        dest
      end

      # The primary SQLite DB for the current environment (member/store
      # data). Absolute path, or nil if it can't be resolved.
      def primary_db_path
        db = ActiveRecord::Base.connection_db_config.database
        db && File.expand_path(db)
      rescue => e
        Rails.logger.error "[SiteSync::BackupManager] primary_db_path failed: #{e.message}"
        nil
      end

      # The encrypted primary-DB blob inside a snapshot dir, or nil. Ignores
      # any (never-written) transient-DB blobs, and prefers the production
      # blob when several exist so restore is deterministic (the production
      # DB is always the disaster-recovery target).
      def encrypted_db_in(snapshot_path)
        blobs = Dir.glob(File.join(snapshot_path, "db", "**", "*.sqlite3.enc")).reject do |f|
          base = File.basename(f)
          TRANSIENT_DB_BASENAMES.any? { |t| base == "#{t}.enc" }
        end
        blobs.find { |f| f.end_with?("db/production/production.sqlite3.enc") } || blobs.first
      end

      def backup_has_encrypted_db?(snapshot_name)
        !encrypted_db_in(resolve_snapshot_path(snapshot_name)).nil?
      rescue BackupError
        false
      end

      private

      # Copy any already-encrypted DB blob(s) present in /site/db into the
      # snapshot at the same relative path. This is how the pulled-down
      # production blob (or a locally staged one) makes it into a portable
      # snapshot. Pure copy — no encryption, no plaintext DB ever included.
      # rsync excluded /db, so we replay just the .enc blobs here.
      def include_encrypted_db_in(backup_dir)
        Dir.glob(File.join(RoeSitePaths::SITE_PATH, "db", "**", "*.sqlite3.enc")).each do |blob|
          base = File.basename(blob)
          next if TRANSIENT_DB_BASENAMES.any? { |t| base == "#{t}.enc" }

          rel  = blob.sub("#{RoeSitePaths::SITE_PATH}/", "")
          dest = File.join(backup_dir, rel)
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(blob, dest)
        end
      end

      def backup_passphrase
        SyncConfig.current.read_backup_passphrase
      rescue => e
        Rails.logger.error "[SiteSync::BackupManager] reading backup passphrase failed: #{e.message}"
        nil
      end

      # Yield a transactionally-consistent copy of the SQLite DB via
      # `VACUUM INTO` (no torn WAL, no -wal/-shm sidecars). Falls back to the
      # live file if VACUUM INTO isn't available, matching the existing
      # rsync-the-live-file behaviour of `rake site:pull_db`. The `yield`
      # sits OUTSIDE the VACUUM rescue so an encryption failure surfaces as
      # itself rather than triggering a spurious fallback re-encrypt.
      def with_consistent_db_copy(src)
        Dir.mktmpdir("roe-dbsnap") do |tmp|
          copy = File.join(tmp, File.basename(src))
          if vacuum_into(copy)
            yield copy
          else
            yield src
          end
        end
      end

      def vacuum_into(dest)
        quoted = dest.gsub("'", "''")
        ActiveRecord::Base.connection.execute("VACUUM INTO '#{quoted}'")
        true
      rescue => e
        Rails.logger.warn "[SiteSync::BackupManager] VACUUM INTO failed (#{e.message}); encrypting DB file directly"
        false
      end

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
        latest = File.join(BACKUP_ROOT, "latest")
        FileUtils.rm_f(latest) if File.symlink?(latest) || File.exist?(latest)
        FileUtils.ln_s(timestamp, latest)
      end

      def write_snapshot_meta(snapshot_dir)
        meta = {
          "fingerprint" => SiteSync::Ledger.fingerprint_for(snapshot_dir),
          "created_at"  => Time.now.utc.iso8601
        }
        File.write(File.join(snapshot_dir, SNAPSHOT_META_FILENAME), JSON.pretty_generate(meta))
      end

      def read_snapshot_fingerprint(snapshot_dir)
        meta_path = File.join(snapshot_dir, SNAPSHOT_META_FILENAME)
        return nil unless File.exist?(meta_path)
        JSON.parse(File.read(meta_path))["fingerprint"]
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
        unless path.start_with?(File.expand_path(BACKUP_ROOT) + "/")
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
          name:          File.basename(path),
          path:          path,
          size:          du_bytes(path),
          created_at:    stat.mtime,
          fingerprint:   fp,
          active:        !current_fingerprint.nil? && !fp.nil? && fp == current_fingerprint,
          encrypted_db:  !encrypted_db_in(path).nil?
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
        Dir.glob(File.join(path, "**", "*"), File::FNM_DOTMATCH).count do |f|
          File.file?(f) && !File.symlink?(f)
        end
      end
    end
  end
end
