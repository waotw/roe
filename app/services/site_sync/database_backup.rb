module SiteSync
  # Client-side pull of the peer's encrypted database blob into the local
  # /site, so a full-site backup always carries a current, restorable DB.
  #
  # One-directional (live → local) and best-effort: it must never raise
  # into the sync flow — the content sync has already succeeded by the time
  # this runs, and a DB-backup hiccup (peer busy, no passphrase set) is not
  # a sync failure. The blob is ciphertext end to end; the plaintext DB
  # never crosses the wire, and this side never decrypts it (that's an
  # explicit restore step with the passphrase).
  class DatabaseBackup
    # Where the pulled blob lands locally — mirrors production's own layout
    # (db/production/production.sqlite3.enc) so a snapshot or deploy finds
    # it exactly where the database belongs.
    def self.local_blob_path
      File.join(RoeSitePaths::SITE_DB_PATH, "production", "production.sqlite3.enc")
    end

    class << self
      # Pull a fresh encrypted DB blob from the peer and write it locally,
      # overwriting the previous one. Returns:
      #   :written      — a valid blob was pulled and stored
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

        write_blob(bytes)
        Rails.logger.info "[SiteSync::DatabaseBackup] stored encrypted DB blob (#{bytes.bytesize}b) at #{local_blob_path}"
        :written
      rescue => e
        Rails.logger.warn "[SiteSync::DatabaseBackup] pull! failed: #{e.class} #{e.message}"
        :error
      end

      private

      def looks_like_blob?(bytes)
        bytes.byteslice(0, SiteSync::BackupCrypto::MAGIC.bytesize) == SiteSync::BackupCrypto::MAGIC
      end

      def write_blob(bytes)
        dest = local_blob_path
        FileUtils.mkdir_p(File.dirname(dest))
        tmp = "#{dest}.tmp-#{SecureRandom.hex(6)}"
        begin
          File.binwrite(tmp, bytes)
          FileUtils.mv(tmp, dest)
        ensure
          FileUtils.rm_f(tmp)
        end
      end
    end
  end
end
