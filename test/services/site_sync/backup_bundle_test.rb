require "test_helper"
require "tmpdir"
require "fileutils"
require "securerandom"

module SiteSync
  class BackupBundleTest < ActiveSupport::TestCase
    PASS = "dr-bundle-passphrase"

    def setup
      @dir     = Dir.mktmpdir("bundle-test")
      @db      = File.join(@dir, "production.sqlite3")
      @secrets = File.join(@dir, "secrets")
      FileUtils.mkdir_p(@secrets)

      @db_bytes  = "SQLite format 3\0" + SecureRandom.random_bytes(2048)
      @mk_bytes  = SecureRandom.hex(16)
      @cred_bytes = SecureRandom.random_bytes(512)
      File.binwrite(@db, @db_bytes)
      File.binwrite(File.join(@secrets, "master.key"), @mk_bytes)
      File.binwrite(File.join(@secrets, "credentials.yml.enc"), @cred_bytes)
    end

    def teardown
      FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
    end

    test "packs db + keys and unpacks them byte-for-byte" do
      enc = File.join(@dir, "bundle.enc")
      BackupBundle.pack(db_path: @db, secrets_dir: @secrets, dest_enc: enc, passphrase: PASS)
      assert BackupCrypto.blob?(enc), "bundle must be a Roe encrypted blob"

      out = File.join(@dir, "restore")
      written = BackupBundle.unpack(enc_path: enc, dest_dir: out, passphrase: PASS)

      assert_equal @db_bytes,   File.binread(written[:db])
      assert_equal @mk_bytes,   File.binread(written[:master_key])
      assert_equal @cred_bytes, File.binread(written[:credentials])
    end

    test "packs the db alone when no secrets are present" do
      empty = File.join(@dir, "no-secrets")
      FileUtils.mkdir_p(empty)
      enc = File.join(@dir, "db-only.enc")
      BackupBundle.pack(db_path: @db, secrets_dir: empty, dest_enc: enc, passphrase: PASS)

      written = BackupBundle.unpack(enc_path: enc, dest_dir: File.join(@dir, "r2"), passphrase: PASS)
      assert_equal @db_bytes, File.binread(written[:db])
      assert_nil written[:master_key]
      assert_nil written[:credentials]
    end

    test "unpacks a LEGACY bare-SQLite .enc (backward compatible)" do
      # Old format: BackupCrypto encrypted the raw sqlite file directly.
      legacy = File.join(@dir, "legacy.enc")
      BackupCrypto.encrypt_file(@db, legacy, PASS)

      written = BackupBundle.unpack(enc_path: legacy, dest_dir: File.join(@dir, "r3"), passphrase: PASS)
      assert_equal @db_bytes, File.binread(written[:db]), "legacy bare-DB backup must still restore"
      assert_nil written[:master_key]
    end

    test "a wrong passphrase raises DecryptError" do
      enc = File.join(@dir, "b.enc")
      BackupBundle.pack(db_path: @db, secrets_dir: @secrets, dest_enc: enc, passphrase: PASS)
      assert_raises(BackupCrypto::DecryptError) do
        BackupBundle.unpack(enc_path: enc, dest_dir: File.join(@dir, "r4"), passphrase: "wrong")
      end
    end
  end
end
