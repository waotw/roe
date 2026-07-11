require "test_helper"
require "tmpdir"
require "fileutils"
require "securerandom"

module SiteSync
  # Focused coverage of the encrypted-DB glue on BackupManager. The full
  # rsync-based `create`/`restore` path needs a real /site tree and rsync,
  # so it's exercised manually; here we verify the DB discovery + decrypt
  # logic against a hand-built snapshot under BACKUP_ROOT.
  class BackupManagerDbTest < ActiveSupport::TestCase
    PASS = "a-strong-backup-passphrase"

    def setup
      @snapshot_name = "2099-01-01-000000-dbtest-#{SecureRandom.hex(4)}"
      @snapshot_path = File.join(BackupManager::BACKUP_ROOT, @snapshot_name)
      FileUtils.mkdir_p(@snapshot_path)

      @plaintext = SecureRandom.random_bytes(2048)
      @scratch   = Dir.mktmpdir("bm-db-test")
    end

    def teardown
      FileUtils.rm_rf(@snapshot_path) if @snapshot_path
      FileUtils.remove_entry(@scratch) if @scratch && Dir.exist?(@scratch)
    end

    # Place an encrypted primary-DB blob in the snapshot, as `create` would.
    def seed_encrypted_db!(rel = "db/production/production.sqlite3.enc")
      src = File.join(@scratch, "source.sqlite3")
      File.binwrite(src, @plaintext)
      dest = File.join(@snapshot_path, rel)
      BackupCrypto.encrypt_file(src, dest, PASS)
      dest
    end

    test "encrypted_db_in finds the primary DB blob" do
      seed_encrypted_db!
      found = BackupManager.encrypted_db_in(@snapshot_path)
      assert found
      assert found.end_with?("production.sqlite3.enc")
    end

    test "encrypted_db_in ignores transient DB blobs" do
      # Only a cache blob present → treated as "no primary DB".
      seed_encrypted_db!("db/production/cache.sqlite3.enc")
      assert_nil BackupManager.encrypted_db_in(@snapshot_path)
    end

    test "encrypted_db_in returns nil when the snapshot has no DB" do
      assert_nil BackupManager.encrypted_db_in(@snapshot_path)
    end

    test "encrypted_db_in prefers the production blob when several exist" do
      seed_encrypted_db!("db/development/development.sqlite3.enc")
      seed_encrypted_db!("db/production/production.sqlite3.enc")
      found = BackupManager.encrypted_db_in(@snapshot_path)
      assert found.end_with?("db/production/production.sqlite3.enc"),
             "production blob must win over a stray dev blob"
    end

    test "backup_has_encrypted_db? reflects presence" do
      refute BackupManager.backup_has_encrypted_db?(@snapshot_name)
      seed_encrypted_db!
      assert BackupManager.backup_has_encrypted_db?(@snapshot_name)
    end

    test "restore_db decrypts the DB into an explicit destination" do
      seed_encrypted_db!
      dest = File.join(@scratch, "restored.sqlite3")

      result = BackupManager.restore_db(@snapshot_name, PASS, dest: dest)
      assert_equal dest, result
      assert_equal @plaintext, File.binread(dest)
    end

    test "restore_db clears stale WAL/shm sidecars at the destination" do
      seed_encrypted_db!
      dest = File.join(@scratch, "restored.sqlite3")
      File.binwrite("#{dest}-wal", "stale")
      File.binwrite("#{dest}-shm", "stale")

      BackupManager.restore_db(@snapshot_name, PASS, dest: dest)
      refute File.exist?("#{dest}-wal"), "stale -wal must be removed"
      refute File.exist?("#{dest}-shm"), "stale -shm must be removed"
    end

    test "restore_db rejects a wrong passphrase without writing the destination" do
      seed_encrypted_db!
      dest = File.join(@scratch, "restored.sqlite3")

      err = assert_raises(BackupManager::BackupError) do
        BackupManager.restore_db(@snapshot_name, "wrong", dest: dest)
      end
      assert_match(/passphrase/i, err.message)
      refute File.exist?(dest), "must not write a destination on a bad passphrase"
    end

    test "restore_db raises when the snapshot has no encrypted DB" do
      err = assert_raises(BackupManager::BackupError) do
        BackupManager.restore_db(@snapshot_name, PASS, dest: File.join(@scratch, "x"))
      end
      assert_match(/no encrypted database/i, err.message)
    end
  end
end
