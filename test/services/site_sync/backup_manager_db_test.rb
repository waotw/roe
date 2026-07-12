require "test_helper"
require "tmpdir"
require "fileutils"
require "securerandom"

module SiteSync
  # Coverage of BackupManager.restore_db against live-database DR bundles under
  # backups/live/database/ (what SiteSync::DatabaseBackup stores). Handles both
  # the current bundle format and legacy bare-SQLite backups.
  # build_encrypted_db_bundle needs a live AR connection, so it's exercised by
  # the endpoint integration test instead.
  class BackupManagerDbTest < ActiveSupport::TestCase
    PASS = "a-strong-backup-passphrase"

    def setup
      @dir  = BackupPaths.live_database
      FileUtils.mkdir_p(@dir)
      @name = "2099-01-01-000000.enc" # matches DatabaseBackup::BACKUP_NAME_RE
      @enc  = File.join(@dir, @name)

      @scratch   = Dir.mktmpdir("bm-db-test")
      @plaintext = "SQLite format 3\0" + SecureRandom.random_bytes(2048)
      @db_src    = File.join(@scratch, "source.sqlite3")
      File.binwrite(@db_src, @plaintext)
    end

    def teardown
      FileUtils.rm_f(@enc)
      FileUtils.remove_entry(@scratch) if @scratch && Dir.exist?(@scratch)
    end

    # Build a DR bundle at @enc, as DatabaseBackup would store one.
    def seed_bundle!
      secrets = File.join(@scratch, "empty-secrets")
      FileUtils.mkdir_p(secrets)
      BackupBundle.pack(db_path: @db_src, secrets_dir: secrets, dest_enc: @enc, passphrase: PASS)
    end

    test "restore_db unpacks the bundle's DB into an explicit destination" do
      seed_bundle!
      dest = File.join(@scratch, "restored.sqlite3")

      result = BackupManager.restore_db(@name, PASS, dest: dest)
      assert_equal dest, result
      assert_equal @plaintext, File.binread(dest)
    end

    test "restore_db clears stale WAL/shm sidecars at the destination" do
      seed_bundle!
      dest = File.join(@scratch, "restored.sqlite3")
      File.binwrite("#{dest}-wal", "stale")
      File.binwrite("#{dest}-shm", "stale")

      BackupManager.restore_db(@name, PASS, dest: dest)
      refute File.exist?("#{dest}-wal"), "stale -wal must be removed"
      refute File.exist?("#{dest}-shm"), "stale -shm must be removed"
    end

    test "restore_db also restores a LEGACY bare-SQLite backup" do
      BackupCrypto.encrypt_file(@db_src, @enc, PASS) # old format: raw sqlite encrypted
      dest = File.join(@scratch, "restored.sqlite3")

      BackupManager.restore_db(@name, PASS, dest: dest)
      assert_equal @plaintext, File.binread(dest)
    end

    test "restore_db rejects a wrong passphrase without writing the destination" do
      seed_bundle!
      dest = File.join(@scratch, "restored.sqlite3")

      err = assert_raises(BackupManager::BackupError) do
        BackupManager.restore_db(@name, "wrong", dest: dest)
      end
      assert_match(/passphrase/i, err.message)
      refute File.exist?(dest), "must not write a destination on a bad passphrase"
    end

    test "restore_db raises when the backup doesn't exist" do
      err = assert_raises(BackupManager::BackupError) do
        BackupManager.restore_db("2099-12-31-235959.enc", PASS, dest: File.join(@scratch, "x"))
      end
      assert_match(/not found/i, err.message)
    end
  end
end
