require "test_helper"
require "tmpdir"
require "fileutils"
require "stringio"
require "securerandom"

module SiteSync
  class PendingRestoreTest < ActiveSupport::TestCase
    PASS = "restore-passphrase"

    def setup
      @dir       = Dir.mktmpdir("pending-restore")
      @db        = File.join(@dir, "production.sqlite3")
      @pending   = "#{@db}#{PendingRestore::PENDING_SUFFIX}"
      @plaintext = "SQLite format 3\0" + SecureRandom.random_bytes(2048)

      @master_key  = SecureRandom.hex(16)
      @credentials = SecureRandom.random_bytes(256)
      @secrets     = File.join(@dir, "secrets")
      FileUtils.mkdir_p(@secrets)
    end

    def teardown
      FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
      SiteSync::RestoreCheck.clear!
    end

    # A full DR bundle: db + master.key + credentials.
    def uploaded_bundle(passphrase = PASS)
      db  = File.join(@dir, "bundle-db.sqlite3")
      sec = File.join(@dir, "bundle-secrets")
      FileUtils.mkdir_p(sec)
      File.binwrite(db, @plaintext)
      File.binwrite(File.join(sec, "master.key"), @master_key)
      File.binwrite(File.join(sec, "credentials.yml.enc"), @credentials)
      enc = File.join(@dir, "bundle.enc")
      BackupBundle.pack(db_path: db, secrets_dir: sec, dest_enc: enc, passphrase: passphrase)
      StringIO.new(File.binread(enc))
    end

    # A legacy bare-SQLite backup (no keys inside).
    def uploaded_bare(passphrase = PASS)
      src = File.join(@dir, "bare.sqlite3")
      enc = File.join(@dir, "bare.enc")
      File.binwrite(src, @plaintext)
      BackupCrypto.encrypt_file(src, enc, passphrase)
      StringIO.new(File.binread(enc))
    end

    test "stage_from_upload stages the DB for the next-boot swap" do
      assert_equal :staged, PendingRestore.stage_from_upload(uploaded_bundle, PASS, dest_db: @db, secrets_dir: @secrets)
      assert File.exist?(@pending)
      assert_equal @plaintext, File.binread(@pending)
    end

    test "stage_from_upload parks the bundle's credentials but does NOT install them" do
      File.binwrite(File.join(@secrets, "master.key"), "LIVE-KEY")
      File.binwrite(File.join(@secrets, "credentials.yml.enc"), "LIVE-CRED")

      PendingRestore.stage_from_upload(uploaded_bundle, PASS, dest_db: @db, secrets_dir: @secrets)

      # Parked (available to apply), not installed.
      assert_equal @master_key,  File.binread(File.join(@secrets, "master.key#{PendingRestore::BACKUP_SUFFIX}"))
      assert_equal @credentials, File.binread(File.join(@secrets, "credentials.yml.enc#{PendingRestore::BACKUP_SUFFIX}"))
      # Live credentials untouched; no key restore-pending staged.
      assert_equal "LIVE-KEY",  File.binread(File.join(@secrets, "master.key"))
      assert_equal "LIVE-CRED", File.binread(File.join(@secrets, "credentials.yml.enc"))
      refute File.exist?(File.join(@secrets, "master.key.restore-pending"))
      assert PendingRestore.backup_credentials_available?(secrets_dir: @secrets)
    end

    test "stage_from_upload rejects a wrong passphrase and stages nothing" do
      assert_equal :wrong_passphrase,
                   PendingRestore.stage_from_upload(uploaded_bundle, "wrong", dest_db: @db, secrets_dir: @secrets)
      refute File.exist?(@pending)
    end

    test "stage_from_upload rejects a non-blob upload" do
      assert_equal :not_a_blob,
                   PendingRestore.stage_from_upload(StringIO.new("not a backup"), PASS, dest_db: @db, secrets_dir: @secrets)
      refute File.exist?(@pending)
    end

    test "apply_if_present! swaps the DB in, preserves the old one, schedules the check" do
      File.binwrite(@db, "OLD-DATABASE-CONTENTS")
      File.binwrite(@pending, @plaintext)
      File.binwrite("#{@db}-wal", "stale")
      File.binwrite("#{@db}-shm", "stale")

      assert_equal :applied, PendingRestore.apply_if_present!(@db)
      assert_equal @plaintext, File.binread(@db), "staged DB is now live"
      refute File.exist?(@pending), "pending consumed"
      refute File.exist?("#{@db}-wal")
      refute File.exist?("#{@db}-shm")

      pre = Dir.glob("#{@db}.pre-restore-*")
      assert_equal 1, pre.size
      assert_equal "OLD-DATABASE-CONTENTS", File.binread(pre.first)
      assert SiteSync::RestoreCheck.needed?, "post-restore self-check scheduled"
    end

    test "apply_if_present! does NOT touch encryption credentials (DB-only)" do
      File.binwrite(@db, "OLD")
      File.binwrite(@pending, @plaintext)
      live_key = File.join(@secrets, "master.key")
      File.binwrite(live_key, "LIVE-KEY")

      PendingRestore.apply_if_present!(@db)

      assert_equal "LIVE-KEY", File.binread(live_key), "live key untouched"
      assert_empty Dir.glob(File.join(@secrets, "master.key.pre-restore-*")), "no key .pre-restore made"
    end

    test "apply_if_present! is a no-op when nothing is staged" do
      File.binwrite(@db, "LIVE")
      assert_equal :none, PendingRestore.apply_if_present!(@db)
      assert_equal "LIVE", File.binread(@db)
    end

    test "legacy bare-SQLite backup stages the DB, with no credentials to park" do
      assert_equal :staged, PendingRestore.stage_from_upload(uploaded_bare, PASS, dest_db: @db, secrets_dir: @secrets)
      assert_equal @plaintext, File.binread(@pending)
      refute PendingRestore.backup_credentials_available?(secrets_dir: @secrets)
    end

    # Write a valid master.key + credentials.yml.enc pair into `dir`.
    def write_valid_pair(dir, master_key: SecureRandom.hex(16))
      mk = File.join(dir, "master.key")
      cr = File.join(dir, "credentials.yml.enc")
      File.write(mk, master_key)
      enc = ActiveSupport::EncryptedConfiguration.new(
        config_path: cr, key_path: mk, env_key: "RAILS_MASTER_KEY", raise_if_missing_key: false
      )
      enc.write({
        "secret_key_base" => "s" * 128,
        "active_record_encryption" => { "primary_key" => "p" * 32, "deterministic_key" => "d" * 32, "key_derivation_salt" => "k" * 32 }
      }.to_yaml)
      [ mk, cr ]
    end

    def park_valid_credentials!
      src = File.join(@dir, "valid-src")
      FileUtils.mkdir_p(src)
      mk, cr = write_valid_pair(src)
      FileUtils.cp(mk, File.join(@secrets, "master.key#{PendingRestore::BACKUP_SUFFIX}"))
      FileUtils.cp(cr, File.join(@secrets, "credentials.yml.enc#{PendingRestore::BACKUP_SUFFIX}"))
    end

    test "apply_backup_credentials! installs + keeps credentials that validate" do
      park_valid_credentials!
      assert_equal :applied, PendingRestore.apply_backup_credentials!(secrets_dir: @secrets)
      refute File.exist?(File.join(@secrets, "master.key#{PendingRestore::BACKUP_SUFFIX}")), "parked consumed"
      assert PendingRestore.credentials_valid?(@secrets)
    end

    test "apply_backup_credentials! reverts to the working pair when parked don't validate" do
      write_valid_pair(@secrets) # the working live pair
      before_key  = File.binread(File.join(@secrets, "master.key"))
      before_cred = File.binread(File.join(@secrets, "credentials.yml.enc"))
      # Parked pair is unusable (empty master.key can't decrypt anything).
      File.binwrite(File.join(@secrets, "master.key#{PendingRestore::BACKUP_SUFFIX}"), "")
      File.binwrite(File.join(@secrets, "credentials.yml.enc#{PendingRestore::BACKUP_SUFFIX}"), "garbage")

      assert_equal :reverted, PendingRestore.apply_backup_credentials!(secrets_dir: @secrets)
      assert_equal before_key,  File.binread(File.join(@secrets, "master.key")), "live key reverted"
      assert_equal before_cred, File.binread(File.join(@secrets, "credentials.yml.enc")), "live credentials reverted"
      assert PendingRestore.credentials_valid?(@secrets), "site keeps working credentials"
    end

    test "apply_backup_credentials! is a no-op when nothing is parked" do
      assert_equal :none, PendingRestore.apply_backup_credentials!(secrets_dir: @secrets)
    end
  end
end
