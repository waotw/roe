require "test_helper"
require "tmpdir"
require "fileutils"
require "securerandom"

module SiteSync
  class DatabaseBackupTest < ActiveSupport::TestCase
    PASS = "a-strong-backup-passphrase"

    def setup
      @dir = BackupPaths.live_database
      FileUtils.rm_rf(@dir)
      @scratch = Dir.mktmpdir("db-backup-test")
    end

    def teardown
      FileUtils.rm_rf(@dir)
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
      src = File.join(@scratch, "src-#{SecureRandom.hex(4)}.sqlite3")
      enc = File.join(@scratch, "src-#{SecureRandom.hex(4)}.enc")
      File.binwrite(src, SecureRandom.random_bytes(1024))
      BackupCrypto.encrypt_file(src, enc, PASS)
      File.binread(enc)
    end

    test "stores a pulled blob as a timestamped backup" do
      bytes  = real_blob_bytes
      result = stub_peer_database(bytes) { DatabaseBackup.pull! }

      assert_equal :written, result
      list = DatabaseBackup.list
      assert_equal 1, list.size
      stored = list.first
      assert_match(/\A\d{4}-\d{2}-\d{2}-\d{6}\.enc\z/, stored[:name])
      assert_equal bytes, File.binread(stored[:path])
      assert BackupCrypto.blob?(stored[:path]), "stored file must be a valid Roe backup blob"
    end

    test "nil response (peer unreachable / no passphrase) stores nothing" do
      result = stub_peer_database(nil) { DatabaseBackup.pull! }
      assert_equal :unavailable, result
      assert_empty DatabaseBackup.list
    end

    test "empty response stores nothing" do
      result = stub_peer_database("".b) { DatabaseBackup.pull! }
      assert_equal :unavailable, result
      assert_empty DatabaseBackup.list
    end

    test "non-blob garbage is rejected, not stored" do
      result = stub_peer_database("this is not a blob".b) { DatabaseBackup.pull! }
      assert_equal :error, result
      assert_empty DatabaseBackup.list, "must never store data that isn't a Roe backup blob"
    end

    test "pull! prunes to the retention limit, keeping the newest" do
      FileUtils.mkdir_p(@dir)
      # Seed in the PAST with increasing mtimes, so the fresh pull below is the
      # newest and the oldest seeds get pruned.
      base = Time.new(2020, 1, 1, 0, 0, 0)
      (1..(DatabaseBackup::RETENTION + 5)).each do |i|
        path = File.join(@dir, format("2020-01-%02d-000000.enc", i))
        File.binwrite(path, "seed")
        t = base + (i * 3600)
        File.utime(t, t, path)
      end

      # A fresh pull writes one more (newest) and prunes back to the limit.
      stub_peer_database(real_blob_bytes) { DatabaseBackup.pull! }

      list = DatabaseBackup.list
      assert_equal DatabaseBackup::RETENTION, list.size
      # The just-pulled backup (today's timestamp) is newest → kept.
      assert_equal Time.now.year.to_s, list.first[:name][0, 4]
    end

    test "resolve refuses a path that escapes the backups dir" do
      assert_nil DatabaseBackup.resolve("../../etc/passwd")
      assert_nil DatabaseBackup.resolve("nope.enc")
    end
  end
end
