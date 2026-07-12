require "tmpdir"
require "fileutils"

module SiteSync
  # Worst-case database restore for the live site. An admin uploads an
  # encrypted DR bundle + passphrase to the PRODUCTION admin over HTTPS; we
  # unpack it to staging files next to the primary DB (and the encryption
  # keys) and apply them on the NEXT boot — before ActiveRecord opens the
  # database or Rails reads credentials. We never overwrite the live DB while
  # the running app holds it open (that would corrupt SQLite); staging +
  # boot-swap is the safe path, and it needs no SSH — just the authenticated
  # upload.
  #
  # A full DR bundle carries the database AND the master.key/credentials it
  # was encrypted under, so a restored DB's encrypted columns (Stripe/Postmark
  # secrets) stay decryptable even on a fresh host whose self-generated keys
  # differ. Restoring therefore swaps BOTH in — the DB and its matching keys
  # are one indivisible pair. Legacy bare-SQLite backups carry no keys; those
  # restore the DB alone (see SiteSync::BackupBundle.unpack auto-detect).
  #
  # The boot-swap itself is inlined in config/application.rb (it must run
  # before autoloading is available); `apply_if_present!` here mirrors that
  # logic exactly and is what the tests exercise. Keep the two in sync.
  class PendingRestore
    PENDING_SUFFIX = ".restore-pending"

    # The bundle's encryption-key files, staged alongside the live ones in the
    # secrets dir. Order matters at apply time only in that keys go in before
    # the DB (so anything reading credentials early sees the restored set).
    KEY_FILES = %w[master.key credentials.yml.enc].freeze

    class << self
      # Decrypt + unpack an uploaded DR bundle to staging files. Returns
      # :staged / :wrong_passphrase / :not_a_blob. `dest_db` is the primary DB
      # path to stage against; `secrets_dir` is where key files stage
      # (both overridable for tests).
      def stage_from_upload(upload, passphrase,
                            dest_db: primary_db_path,
                            secrets_dir: RoeSitePaths::SITE_SYSTEM_SECRETS_PATH)
        Dir.mktmpdir("roe-restore-upload") do |dir|
          enc = File.join(dir, "upload.enc")
          File.binwrite(enc, upload.read)

          return :not_a_blob       unless SiteSync::BackupCrypto.blob?(enc)
          return :wrong_passphrase unless SiteSync::BackupCrypto.verify(enc, passphrase.to_s)

          unpacked = File.join(dir, "unpacked")
          written  = SiteSync::BackupBundle.unpack(enc_path: enc, dest_dir: unpacked, passphrase: passphrase.to_s)
          return :not_a_blob unless written[:db] # decrypted but no DB inside — unusable

          # Stage the DB; applied on the next boot.
          pending_db = "#{dest_db}#{PENDING_SUFFIX}"
          FileUtils.mkdir_p(File.dirname(pending_db))
          FileUtils.cp(written[:db], pending_db)

          # Stage the bundle's keys, if it carried them, to apply on the same
          # boot. Absent from a legacy bare-DB backup → DB stages alone.
          FileUtils.mkdir_p(secrets_dir)
          { master_key: "master.key", credentials: "credentials.yml.enc" }.each do |key, fname|
            next unless written[key]
            FileUtils.cp(written[key], File.join(secrets_dir, "#{fname}#{PENDING_SUFFIX}"))
          end

          :staged
        end
      end

      # Apply a staged restore: preserve the current DB/keys as .pre-restore-<ts>
      # copies (for undo), move the staged files into place, and clear stale
      # WAL/shm. Safe no-op when nothing is staged. Returns :applied / :none.
      # MIRRORED by the inline block in config/application.rb — keep in sync.
      def apply_if_present!(db_path = primary_db_path,
                            secrets_dir: RoeSitePaths::SITE_SYSTEM_SECRETS_PATH)
        ts      = Time.now.strftime("%Y%m%d%H%M%S")
        applied = false

        # Keys first, so anything that reads credentials at boot sees the
        # restored set. Each is a matched pair with the DB below.
        KEY_FILES.each do |fname|
          pending = File.join(secrets_dir, "#{fname}#{PENDING_SUFFIX}")
          next unless File.exist?(pending)

          live = File.join(secrets_dir, fname)

          # Bundled key already matches the host's → same install. Keep the
          # existing key and drop the staged copy: no swap, and no leftover
          # exact-duplicate key lying around.
          if File.exist?(live) && FileUtils.identical?(pending, live)
            FileUtils.rm_f(pending)
            next
          end

          # Different (or the host has none) → the bundled key is the one that
          # matches the restored DB's encrypted columns. Rename the old key to
          # a .pre-restore-<ts> copy (cautious), then install the bundled one.
          FileUtils.mv(live, "#{live}.pre-restore-#{ts}") if File.exist?(live)
          FileUtils.mv(pending, live)
          File.chmod(0o600, live)
          applied = true
        end

        # Then the database.
        pending_db = "#{db_path}#{PENDING_SUFFIX}"
        if File.exist?(pending_db)
          FileUtils.mkdir_p(File.dirname(db_path))
          FileUtils.mv(db_path, "#{db_path}.pre-restore-#{ts}") if File.exist?(db_path)
          FileUtils.mv(pending_db, db_path)
          [ "#{db_path}-wal", "#{db_path}-shm" ].each { |f| FileUtils.rm_f(f) }
          applied = true
        end

        applied ? :applied : :none
      end

      def pending?
        File.exist?("#{primary_db_path}#{PENDING_SUFFIX}")
      end

      def clear!(secrets_dir: RoeSitePaths::SITE_SYSTEM_SECRETS_PATH)
        FileUtils.rm_f("#{primary_db_path}#{PENDING_SUFFIX}")
        KEY_FILES.each { |f| FileUtils.rm_f(File.join(secrets_dir, "#{f}#{PENDING_SUFFIX}")) }
      end

      # Derived the same way database.yml + the boot block do, so the
      # controller (staging) and boot (applying) always agree on the path.
      def primary_db_path
        File.join(RoeSitePaths::SITE_DB_PATH, Rails.env, "#{Rails.env}.sqlite3")
      end
    end
  end
end
