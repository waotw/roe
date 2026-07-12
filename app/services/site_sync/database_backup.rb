require "fileutils"
require "securerandom"

module SiteSync
  # Client-side pull of the live site's encrypted database DR bundle, stored
  # locally as a timestamped, retention-capped series under
  # backups/live/database/. This is the "Live Site" backup list in the admin
  # UI — a running history of the live database, captured every sync.
  #
  # One-directional (live → local) and best-effort: it must never raise into
  # the sync flow — the content sync has already succeeded by the time this
  # runs, and a DB-backup hiccup (peer busy, no passphrase set) is not a sync
  # failure. Each blob is a self-contained DR bundle (DB + master.key +
  # credentials, see SiteSync::BackupBundle), ciphertext end to end; the
  # plaintext DB never crosses the wire, and this side never decrypts it
  # (that's an explicit restore step with the passphrase).
  class DatabaseBackup
    # Keep this many live-DB backups locally; older ones are pruned after
    # each successful pull. Matches BackupManager::BACKUP_RETENTION so the two
    # histories stay comparable in depth.
    RETENTION = 15

    # Match the timestamped filenames we write, so listing/pruning/resolve
    # ignore anything else that lands in the directory.
    BACKUP_NAME_RE = /\A\d{4}-\d{2}-\d{2}-\d{6}\.enc\z/.freeze

    class << self
      # Pull a fresh encrypted DB bundle from the peer and store it as a new
      # timestamped backup, pruning old ones. Returns:
      #   :written      — a valid bundle was pulled and stored
      #   :unavailable  — nothing to pull (peer unreachable or no passphrase)
      #   :error        — a response arrived but wasn't a usable blob
      def pull!
        bytes = Exchange.pull_peer_database
        return :unavailable if bytes.nil? || bytes.empty?

        # Refuse to store anything that isn't a Roe backup blob, so a
        # misrouted or garbage response can never masquerade as the DB.
        unless looks_like_blob?(bytes)
          Rails.logger.warn "[SiteSync::DatabaseBackup] peer returned non-blob data (#{bytes.bytesize}b); ignoring"
          return :error
        end

        dest = write_blob(bytes)
        prune!
        Rails.logger.info "[SiteSync::DatabaseBackup] stored live DB backup (#{bytes.bytesize}b) at #{dest}"
        :written
      rescue => e
        Rails.logger.warn "[SiteSync::DatabaseBackup] pull! failed: #{e.class} #{e.message}"
        :error
      end

      # Newest-first list of stored live-DB backups, for the admin UI. Each
      # entry: { name:, path:, size:, created_at: }.
      def list
        dir = SiteSync::BackupPaths.live_database
        return [] unless Dir.exist?(dir)

        Dir.children(dir)
           .select { |n| n =~ BACKUP_NAME_RE }
           .map    { |n| describe(File.join(dir, n)) }
           .sort_by { |b| -b[:created_at].to_i }
      end

      def latest
        list.first
      end

      # Resolve a backup name to an absolute path, or nil. Defense in depth:
      # refuse any name that escapes the backups dir (e.g. "../../etc/...").
      def resolve(name)
        dir  = SiteSync::BackupPaths.live_database
        path = File.expand_path(File.join(dir, name.to_s))
        return nil unless path.start_with?(File.expand_path(dir) + "/")
        return nil unless File.file?(path)
        path
      end

      private

      def describe(path)
        stat = File.stat(path)
        { name: File.basename(path), path: path, size: stat.size, created_at: stat.mtime }
      end

      def looks_like_blob?(bytes)
        bytes.byteslice(0, SiteSync::BackupCrypto::MAGIC.bytesize) == SiteSync::BackupCrypto::MAGIC
      end

      def write_blob(bytes)
        dir = SiteSync::BackupPaths.live_database
        FileUtils.mkdir_p(dir)

        dest = File.join(dir, "#{Time.now.strftime('%Y-%m-%d-%H%M%S')}.enc")
        tmp  = "#{dest}.tmp-#{SecureRandom.hex(6)}"
        begin
          File.binwrite(tmp, bytes)
          FileUtils.mv(tmp, dest)
        ensure
          FileUtils.rm_f(tmp)
        end
        dest
      end

      def prune!
        backups = list
        return if backups.size <= RETENTION

        backups[RETENTION..].each do |b|
          FileUtils.rm_f(b[:path])
          Rails.logger.info "[SiteSync::DatabaseBackup] pruned old live DB backup: #{b[:name]}"
        end
      end
    end
  end
end
