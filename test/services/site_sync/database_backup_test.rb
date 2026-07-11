require "test_helper"
require "fileutils"
require "securerandom"

module SiteSync
  class DatabaseBackupTest < ActiveSupport::TestCase
    PASS = "a-strong-backup-passphrase"

    def setup
      @dest = DatabaseBackup.local_blob_path
      FileUtils.rm_f(@dest)
      @scratch = Dir.mktmpdir("db-backup-test")
    end

    def teardown
      FileUtils.rm_f(@dest)
      FileUtils.remove_entry(@scratch) if @scratch && Dir.exist?(@scratch)
    end

    # Temporarily replace Exchange.pull_peer_database with a canned value,
    # restoring the real singleton method afterwards. (Avoids requiring
    # minitest/mock, which trips this project's test-runner arg parsing.)
    def stub_peer_database(value)
      sc = Exchange.singleton_class
      sc.send(:alias_method, :__orig_pull_peer_database, :pull_peer_database)
      sc.send(:define_method, :pull_peer_database) { value }
      yield
    ensure
      sc.send(:alias_method, :pull_peer_database, :__orig_pull_peer_database)
      sc.send(:remove_method, :__orig_pull_peer_database)
    end

    # A real encrypted blob's bytes, for the happy path.
    def real_blob_bytes
      src = File.join(@scratch, "src.sqlite3")
      enc = File.join(@scratch, "src.enc")
      File.binwrite(src, SecureRandom.random_bytes(1024))
      BackupCrypto.encrypt_file(src, enc, PASS)
      File.binread(enc)
    end

    test "writes a pulled blob to the local production blob path" do
      bytes = real_blob_bytes
      result = stub_peer_database(bytes) { DatabaseBackup.pull! }

      assert_equal :written, result
      assert File.exist?(@dest)
      assert_equal bytes, File.binread(@dest)
      assert BackupCrypto.blob?(@dest), "stored file must be a valid Roe backup blob"
    end

    test "overwrites the previous blob" do
      first  = real_blob_bytes
      stub_peer_database(first) { DatabaseBackup.pull! }
      second = real_blob_bytes
      stub_peer_database(second) { DatabaseBackup.pull! }

      assert_equal second, File.binread(@dest)
    end

    test "nil response (peer unreachable / no passphrase) writes nothing" do
      result = stub_peer_database(nil) { DatabaseBackup.pull! }
      assert_equal :unavailable, result
      refute File.exist?(@dest)
    end

    test "empty response writes nothing" do
      result = stub_peer_database("".b) { DatabaseBackup.pull! }
      assert_equal :unavailable, result
      refute File.exist?(@dest)
    end

    test "non-blob garbage is rejected, not stored" do
      result = stub_peer_database("this is not a blob".b) { DatabaseBackup.pull! }
      assert_equal :error, result
      refute File.exist?(@dest), "must never store data that isn't a Roe backup blob"
    end
  end
end
