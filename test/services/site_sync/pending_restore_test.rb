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
      @plaintext = SecureRandom.random_bytes(2048)

      # For the full-DR-bundle tests.
      @master_key  = SecureRandom.hex(16)
      @credentials = SecureRandom.random_bytes(256)
      @secrets     = File.join(@dir, "secrets")
      FileUtils.mkdir_p(@secrets)
    end

    def teardown
      FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
    end

    # An "uploaded" encrypted blob of @plaintext, as an IO with #read.
    def uploaded_blob(passphrase = PASS)
      src = File.join(@dir, "src.sqlite3")
      enc = File.join(@dir, "src.enc")
      File.binwrite(src, @plaintext)
      BackupCrypto.encrypt_file(src, enc, passphrase)
      StringIO.new(File.binread(enc))
    end

    test "stage_from_upload decrypts a valid blob to the pending file" do
      result = PendingRestore.stage_from_upload(uploaded_blob, PASS, dest_db: @db)
      assert_equal :staged, result
      assert File.exist?(@pending)
      assert_equal @plaintext, File.binread(@pending), "pending file is the decrypted DB"
    end

    test "stage_from_upload rejects a wrong passphrase and stages nothing" do
      result = PendingRestore.stage_from_upload(uploaded_blob, "wrong", dest_db: @db)
      assert_equal :wrong_passphrase, result
      refute File.exist?(@pending)
    end

    test "stage_from_upload rejects a non-blob upload" do
      result = PendingRestore.stage_from_upload(StringIO.new("not a backup"), PASS, dest_db: @db)
      assert_equal :not_a_blob, result
      refute File.exist?(@pending)
    end

    test "apply_if_present! swaps the staged DB in and preserves the old one" do
      File.binwrite(@db, "OLD-DATABASE-CONTENTS")
      File.binwrite(@pending, @plaintext)
      # Stale sidecars that must be cleared so SQLite can't replay an old log.
      File.binwrite("#{@db}-wal", "stale")
      File.binwrite("#{@db}-shm", "stale")

      assert_equal :applied, PendingRestore.apply_if_present!(@db)
      assert_equal @plaintext, File.binread(@db), "staged DB is now the live DB"
      refute File.exist?(@pending), "pending file consumed"
      refute File.exist?("#{@db}-wal"), "stale -wal cleared"
      refute File.exist?("#{@db}-shm"), "stale -shm cleared"

      pre = Dir.glob("#{@db}.pre-restore-*")
      assert_equal 1, pre.size, "old DB preserved as a .pre-restore copy"
      assert_equal "OLD-DATABASE-CONTENTS", File.binread(pre.first)
    end

    test "apply_if_present! is a no-op when nothing is staged" do
      File.binwrite(@db, "LIVE")
      assert_equal :none, PendingRestore.apply_if_present!(@db)
      assert_equal "LIVE", File.binread(@db)
    end

    test "staging then applying round-trips the uploaded database" do
      PendingRestore.stage_from_upload(uploaded_blob, PASS, dest_db: @db)
      PendingRestore.apply_if_present!(@db)
      assert_equal @plaintext, File.binread(@db)
    end

    # A full DR bundle upload: DB + master.key + credentials, as production builds.
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

    test "stage_from_upload on a full bundle stages both the DB and the keys" do
      result = PendingRestore.stage_from_upload(uploaded_bundle, PASS, dest_db: @db, secrets_dir: @secrets)
      assert_equal :staged, result
      assert_equal @plaintext,   File.binread(@pending)
      assert_equal @master_key,  File.binread(File.join(@secrets, "master.key#{PendingRestore::PENDING_SUFFIX}"))
      assert_equal @credentials, File.binread(File.join(@secrets, "credentials.yml.enc#{PendingRestore::PENDING_SUFFIX}"))
    end

    test "apply_if_present! swaps in the DB and keys, preserving the old ones" do
      File.binwrite(@db, "OLD-DB")
      File.binwrite(File.join(@secrets, "master.key"), "OLD-KEY")
      File.binwrite(File.join(@secrets, "credentials.yml.enc"), "OLD-CRED")
      PendingRestore.stage_from_upload(uploaded_bundle, PASS, dest_db: @db, secrets_dir: @secrets)

      assert_equal :applied, PendingRestore.apply_if_present!(@db, secrets_dir: @secrets)
      assert_equal @plaintext,   File.binread(@db)
      assert_equal @master_key,  File.binread(File.join(@secrets, "master.key"))
      assert_equal @credentials, File.binread(File.join(@secrets, "credentials.yml.enc"))

      assert_equal 1, Dir.glob("#{@db}.pre-restore-*").size, "old DB preserved"
      assert_equal 1, Dir.glob(File.join(@secrets, "master.key.pre-restore-*")).size, "old master.key preserved"
      assert_equal 1, Dir.glob(File.join(@secrets, "credentials.yml.enc.pre-restore-*")).size, "old credentials preserved"
    end

    test "apply_if_present! keeps host keys and leaves no duplicate when bundled keys match" do
      # Host already holds the SAME keys as the bundle (same install).
      File.binwrite(@db, "OLD-DB")
      File.binwrite(File.join(@secrets, "master.key"), @master_key)
      File.binwrite(File.join(@secrets, "credentials.yml.enc"), @credentials)
      PendingRestore.stage_from_upload(uploaded_bundle, PASS, dest_db: @db, secrets_dir: @secrets)

      PendingRestore.apply_if_present!(@db, secrets_dir: @secrets)

      assert_equal @master_key,  File.binread(File.join(@secrets, "master.key"))
      assert_equal @credentials, File.binread(File.join(@secrets, "credentials.yml.enc"))
      # Staged copies consumed; no exact-duplicate keys left lying around.
      assert_empty Dir.glob(File.join(@secrets, "*#{PendingRestore::PENDING_SUFFIX}")), "staged keys must be consumed"
      assert_empty Dir.glob(File.join(@secrets, "master.key.pre-restore-*")), "no duplicate master.key left behind"
      assert_empty Dir.glob(File.join(@secrets, "credentials.yml.enc.pre-restore-*")), "no duplicate credentials left behind"
    end
  end
end
