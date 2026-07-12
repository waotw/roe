require "test_helper"
require "fileutils"
require "securerandom"

# The per-backup "Decrypt database" download: decrypts a local backup's
# encrypted blob and streams the plaintext back, without touching the
# live/dev DB. Wrong passphrase must fail cleanly.
class SiteSyncDecryptBackupTest < ActionDispatch::IntegrationTest
  PASS = "decrypt-download-passphrase"

  def setup
    sign_in_as(users(:one))
    @name = "2099-02-02-000000.enc"
    @enc  = File.join(SiteSync::BackupPaths.live_database, @name)
    FileUtils.mkdir_p(File.dirname(@enc))

    @plaintext = "SQLite format 3\0" + SecureRandom.random_bytes(2048)
    @scratch   = Dir.mktmpdir("decrypt-test")
    db  = File.join(@scratch, "src.sqlite3")
    sec = File.join(@scratch, "secrets")
    FileUtils.mkdir_p(sec)
    File.binwrite(db, @plaintext)
    # A real DR bundle, as DatabaseBackup would store one.
    SiteSync::BackupBundle.pack(db_path: db, secrets_dir: sec, dest_enc: @enc, passphrase: PASS)
  end

  def teardown
    FileUtils.rm_f(@enc)
    FileUtils.remove_entry(@scratch) if @scratch && Dir.exist?(@scratch)
  end

  test "decrypts and downloads the database with the correct passphrase" do
    post admin_decrypt_backup_database_path, params: { name: @name, passphrase: PASS }
    assert_response :success
    disposition = response.headers["Content-Disposition"]
    assert_match(/attachment/, disposition)
    assert_match(/#{Regexp.escape("#{@name}-production.sqlite3")}/, disposition)
    assert_equal @plaintext, response.body, "downloaded bytes must equal the decrypted DB"
  end

  test "a wrong passphrase redirects with an alert and downloads nothing" do
    post admin_decrypt_backup_database_path, params: { name: @name, passphrase: "wrong" }
    assert_redirected_to admin_site_sync_path
    assert_match(/passphrase/i, flash[:alert])
  end

  test "an unknown backup name fails cleanly" do
    post admin_decrypt_backup_database_path, params: { name: "2099-01-01-000000-nope", passphrase: PASS }
    assert_redirected_to admin_site_sync_path
    assert flash[:alert].present?
  end
end
