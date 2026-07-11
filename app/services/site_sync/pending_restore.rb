require "tmpdir"
require "fileutils"

module SiteSync
  # Worst-case database restore for the live site. An admin uploads an
  # encrypted backup blob + passphrase to the PRODUCTION admin over HTTPS;
  # we decrypt it to a staging file next to the primary DB and apply it on
  # the NEXT boot — before ActiveRecord opens the database. We never
  # overwrite the live DB while the running app holds it open (that would
  # corrupt SQLite); staging + boot-swap is the safe path, and it needs no
  # SSH — just the authenticated upload.
  #
  # The boot-swap itself is inlined in config/application.rb (it must run
  # before autoloading is available); `apply_if_present!` here mirrors that
  # logic exactly and is what the tests exercise. Keep the two in sync.
  class PendingRestore
    PENDING_SUFFIX = ".restore-pending"

    class << self
      # Decrypt an uploaded encrypted-DB blob to the staging file. Returns
      # :staged / :wrong_passphrase / :not_a_blob. `dest_db` is the primary
      # DB path to stage against (overridable for tests).
      def stage_from_upload(upload, passphrase, dest_db: primary_db_path)
        Dir.mktmpdir("roe-restore-upload") do |dir|
          enc = File.join(dir, "upload.enc")
          File.binwrite(enc, upload.read)

          return :not_a_blob       unless SiteSync::BackupCrypto.blob?(enc)
          return :wrong_passphrase unless SiteSync::BackupCrypto.verify(enc, passphrase.to_s)

          pending = "#{dest_db}#{PENDING_SUFFIX}"
          FileUtils.mkdir_p(File.dirname(pending))
          SiteSync::BackupCrypto.decrypt_file(enc, pending, passphrase.to_s)
          :staged
        end
      end

      # Apply a staged restore: back up the current DB to a .pre-restore-<ts>
      # copy (for undo), move the staged DB into place, and clear stale
      # WAL/shm. Safe no-op when nothing is staged. Returns :applied / :none.
      # MIRRORED by the inline block in config/application.rb — keep in sync.
      def apply_if_present!(db_path = primary_db_path)
        pending = "#{db_path}#{PENDING_SUFFIX}"
        return :none unless File.exist?(pending)

        if File.exist?(db_path)
          FileUtils.mv(db_path, "#{db_path}.pre-restore-#{Time.now.strftime('%Y%m%d%H%M%S')}")
        end
        FileUtils.mkdir_p(File.dirname(db_path))
        FileUtils.mv(pending, db_path)
        [ "#{db_path}-wal", "#{db_path}-shm" ].each { |f| FileUtils.rm_f(f) }
        :applied
      end

      def pending?
        File.exist?("#{primary_db_path}#{PENDING_SUFFIX}")
      end

      def clear!
        FileUtils.rm_f("#{primary_db_path}#{PENDING_SUFFIX}")
      end

      # Derived the same way database.yml + the boot block do, so the
      # controller (staging) and boot (applying) always agree on the path.
      def primary_db_path
        File.join(RoeSitePaths::SITE_DB_PATH, Rails.env, "#{Rails.env}.sqlite3")
      end
    end
  end
end
