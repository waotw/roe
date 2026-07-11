require "test_helper"
require "tmpdir"
require "fileutils"
require "securerandom"

module SiteSync
  class BackupCryptoTest < ActiveSupport::TestCase
    PASS = "correct horse battery staple"

    def setup
      @dir = Dir.mktmpdir("backup-crypto")
    end

    def teardown
      FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
    end

    def path(name)
      File.join(@dir, name)
    end

    # Write `bytes` of pseudo-random binary to simulate a sqlite file.
    def make_source(name = "production.sqlite3", bytes = 4096)
      p = path(name)
      File.binwrite(p, SecureRandom.random_bytes(bytes))
      p
    end

    test "round-trips a file byte-for-byte" do
      src = make_source
      enc = path("db.enc")
      dec = path("db.out")

      BackupCrypto.encrypt_file(src, enc, PASS)
      assert File.exist?(enc), "encrypted blob should be written"
      refute_equal File.binread(src), File.binread(enc), "blob must not be plaintext"

      BackupCrypto.decrypt_file(enc, dec, PASS)
      assert_equal File.binread(src), File.binread(dec), "decrypted bytes must match source"
    end

    test "round-trips a multi-chunk file (spans CHUNK boundary)" do
      # A few chunks plus a partial one, to exercise the streaming loop.
      src = make_source("big.sqlite3", (BackupCrypto::CHUNK * 3) + 123)
      enc = path("big.enc")
      dec = path("big.out")

      BackupCrypto.encrypt_file(src, enc, PASS)
      BackupCrypto.decrypt_file(enc, dec, PASS)
      assert_equal File.binread(src), File.binread(dec)
    end

    test "round-trips an empty file" do
      src = path("empty.sqlite3")
      File.binwrite(src, "")
      enc = path("empty.enc")
      dec = path("empty.out")

      BackupCrypto.encrypt_file(src, enc, PASS)
      BackupCrypto.decrypt_file(enc, dec, PASS)
      assert_equal "", File.binread(dec)
    end

    test "wrong passphrase raises DecryptError and writes no plaintext" do
      src = make_source
      enc = path("db.enc")
      dec = path("db.out")
      BackupCrypto.encrypt_file(src, enc, PASS)

      assert_raises(BackupCrypto::DecryptError) do
        BackupCrypto.decrypt_file(enc, dec, "wrong passphrase")
      end
      refute File.exist?(dec), "must not leave a partial/plaintext file on failure"
    end

    test "a flipped ciphertext byte is detected (tamper-evident)" do
      src = make_source
      enc = path("db.enc")
      dec = path("db.out")
      BackupCrypto.encrypt_file(src, enc, PASS)

      blob  = File.binread(enc)
      # Flip a byte inside the ciphertext region (past the 34-byte header,
      # before the 16-byte trailing tag).
      i = BackupCrypto::HEADER_LEN + 2
      blob[i] = (blob[i].ord ^ 0x01).chr
      File.binwrite(enc, blob)

      assert_raises(BackupCrypto::DecryptError) do
        BackupCrypto.decrypt_file(enc, dec, PASS)
      end
    end

    test "a corrupted header is rejected as a format error" do
      src = make_source
      enc = path("db.enc")
      BackupCrypto.encrypt_file(src, enc, PASS)

      blob = File.binread(enc)
      blob[0] = (blob[0].ord ^ 0xFF).chr # break the magic
      File.binwrite(enc, blob)

      assert_raises(BackupCrypto::FormatError) do
        BackupCrypto.decrypt_file(enc, path("x.out"), PASS)
      end
    end

    test "a too-small file is a format error, not a crash" do
      junk = path("junk.enc")
      File.binwrite(junk, "nope")
      assert_raises(BackupCrypto::FormatError) do
        BackupCrypto.decrypt_file(junk, path("x.out"), PASS)
      end
    end

    test "blank passphrase is rejected on both encrypt and decrypt" do
      src = make_source
      enc = path("db.enc")
      assert_raises(BackupCrypto::Error) { BackupCrypto.encrypt_file(src, enc, "") }

      BackupCrypto.encrypt_file(src, enc, PASS)
      assert_raises(BackupCrypto::Error) { BackupCrypto.decrypt_file(enc, path("x.out"), "") }
    end

    test "verify confirms a good passphrase without writing plaintext" do
      src = make_source
      enc = path("db.enc")
      BackupCrypto.encrypt_file(src, enc, PASS)

      assert BackupCrypto.verify(enc, PASS)
      refute BackupCrypto.verify(enc, "nope")
    end

    test "blob? recognises Roe blobs and rejects arbitrary files" do
      src = make_source
      enc = path("db.enc")
      BackupCrypto.encrypt_file(src, enc, PASS)

      assert BackupCrypto.blob?(enc)
      refute BackupCrypto.blob?(src)          # a raw sqlite-ish file
      refute BackupCrypto.blob?(path("nope")) # missing file
    end

    test "each encryption uses a fresh salt and iv (distinct blobs)" do
      src = make_source
      a = path("a.enc")
      b = path("b.enc")
      BackupCrypto.encrypt_file(src, a, PASS)
      BackupCrypto.encrypt_file(src, b, PASS)
      refute_equal File.binread(a), File.binread(b),
                   "same input + passphrase must still produce distinct ciphertext"
    end
  end
end
