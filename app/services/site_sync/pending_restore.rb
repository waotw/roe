require "tmpdir"
require "fileutils"

module SiteSync
  # Worst-case database restore for the live site. An admin uploads an
  # encrypted DR bundle + passphrase to the PRODUCTION admin over HTTPS; we
  # unpack it, stage the DATABASE to swap in on the next boot (never overwrite
  # the DB the running app holds open), and PARK the bundle's encryption
  # credentials alongside — but do NOT install them.
  #
  # Restore is deliberately DB-only. Auto-swapping the credential files at boot
  # once clobbered a live site (an empty/decoy master.key on a Kamal host got
  # installed over the good one, and the boot bootstrap then destroyed the
  # credentials). Same-install restores already have the right credentials, so
  # nothing else is needed. When the restored DB's encrypted columns genuinely
  # can't be read (a fresh host), SiteSync::RestoreCheck flags it and the admin
  # explicitly applies the parked credentials via a validated, revertible step.
  #
  # The boot-swap of the DB is inlined in config/application.rb (it must run
  # before autoloading); `apply_if_present!` here mirrors that logic and is
  # what the tests exercise. Keep the two in sync.
  class PendingRestore
    PENDING_SUFFIX = ".restore-pending" # DB staged for the next-boot swap
    BACKUP_SUFFIX  = ".from-backup"     # bundle credentials parked (not installed)

    KEY_FILES = %w[master.key credentials.yml.enc].freeze

    class << self
      # Decrypt + unpack an uploaded DR bundle. Stages the DB and parks the
      # bundle's credentials. Returns :staged / :wrong_passphrase / :not_a_blob.
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

          # Stage the DB for the next-boot swap.
          pending_db = "#{dest_db}#{PENDING_SUFFIX}"
          FileUtils.mkdir_p(File.dirname(pending_db))
          FileUtils.cp(written[:db], pending_db)

          # Park the bundle's credentials — extracted, NOT installed. They're
          # the source for an explicit "apply backup credentials" step if the
          # restored DB's encrypted data turns out to be unreadable here.
          FileUtils.mkdir_p(secrets_dir)
          { master_key: "master.key", credentials: "credentials.yml.enc" }.each do |key, fname|
            next unless written[key]
            FileUtils.cp(written[key], File.join(secrets_dir, "#{fname}#{BACKUP_SUFFIX}"))
          end

          :staged
        end
      end

      # Apply a staged DB restore: preserve the current DB as a .pre-restore-<ts>
      # copy, move the staged DB into place, clear stale WAL/shm, and schedule
      # the post-boot credential self-check. DB-only — credentials are never
      # touched here. Safe no-op when nothing is staged. Returns :applied /
      # :none. MIRRORED by the inline block in config/application.rb.
      def apply_if_present!(db_path = primary_db_path)
        pending_db = "#{db_path}#{PENDING_SUFFIX}"
        return :none unless File.exist?(pending_db)

        ts = Time.now.strftime("%Y%m%d%H%M%S")
        FileUtils.mkdir_p(File.dirname(db_path))
        FileUtils.mv(db_path, "#{db_path}.pre-restore-#{ts}") if File.exist?(db_path)
        FileUtils.mv(pending_db, db_path)
        [ "#{db_path}-wal", "#{db_path}-shm" ].each { |f| FileUtils.rm_f(f) }

        SiteSync::RestoreCheck.mark_needed!
        :applied
      end

      def pending?
        File.exist?("#{primary_db_path}#{PENDING_SUFFIX}")
      end

      # True when a bundle's credentials are parked and available to apply.
      def backup_credentials_available?(secrets_dir: RoeSitePaths::SITE_SYSTEM_SECRETS_PATH)
        KEY_FILES.any? { |f| File.exist?(File.join(secrets_dir, "#{f}#{BACKUP_SUFFIX}")) }
      end

      # Install the parked backup credentials, then VALIDATE them (they must
      # decrypt to a usable active_record_encryption.primary_key). Keep them
      # only if valid; otherwise REVERT to the previous pair so the site stays
      # up. The previous pair is preserved as .pre-restore-<ts> on success.
      # Returns :applied / :reverted / :none. MIRRORED by the inline block in
      # config/application.rb (which runs before autoloading). Keep in sync.
      def apply_backup_credentials!(secrets_dir: RoeSitePaths::SITE_SYSTEM_SECRETS_PATH)
        parked = KEY_FILES.select { |f| File.exist?(File.join(secrets_dir, "#{f}#{BACKUP_SUFFIX}")) }
        return :none if parked.empty?

        ts    = Time.now.strftime("%Y%m%d%H%M%S")
        saved = {} # fname => .pre-restore path, for revert
        parked.each do |f|
          live = File.join(secrets_dir, f)
          if File.exist?(live)
            pre = "#{live}.pre-restore-#{ts}"
            FileUtils.cp(live, pre)
            saved[f] = pre
          end
          FileUtils.cp(File.join(secrets_dir, "#{f}#{BACKUP_SUFFIX}"), live)
          File.chmod(0o600, live)
        end

        if credentials_valid?(secrets_dir)
          parked.each { |f| FileUtils.rm_f(File.join(secrets_dir, "#{f}#{BACKUP_SUFFIX}")) }
          :applied
        else
          saved.each { |f, pre| FileUtils.cp(pre, File.join(secrets_dir, f)); FileUtils.rm_f(pre) }
          :reverted
        end
      end

      # Can credentials.yml.enc in secrets_dir be decrypted to a usable AR
      # primary_key with the master.key beside it? (The validation gate.)
      def credentials_valid?(secrets_dir)
        require "active_support/encrypted_configuration"
        enc = ActiveSupport::EncryptedConfiguration.new(
          config_path: File.join(secrets_dir, "credentials.yml.enc"),
          key_path:    File.join(secrets_dir, "master.key"),
          env_key:     "RAILS_MASTER_KEY",
          raise_if_missing_key: false
        )
        enc.config.dig(:active_record_encryption, :primary_key).present?
      rescue StandardError
        false
      end

      # Abort a staged restore: drop the staged DB and parked credentials.
      def clear!(secrets_dir: RoeSitePaths::SITE_SYSTEM_SECRETS_PATH)
        FileUtils.rm_f("#{primary_db_path}#{PENDING_SUFFIX}")
        KEY_FILES.each { |f| FileUtils.rm_f(File.join(secrets_dir, "#{f}#{BACKUP_SUFFIX}")) }
      end

      # Derived the same way database.yml + the boot block do, so the
      # controller (staging) and boot (applying) always agree on the path.
      def primary_db_path
        File.join(RoeSitePaths::SITE_DB_PATH, Rails.env, "#{Rails.env}.sqlite3")
      end
    end
  end
end
