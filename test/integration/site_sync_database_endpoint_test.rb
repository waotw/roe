require "test_helper"
require "fileutils"

# End-to-end coverage of POST /api/site_sync/database — the one endpoint
# that emits database bytes. It must: require the bearer token, emit ONLY
# decryptable ciphertext (never the raw DB), and 204 when no passphrase is
# set (so plaintext never leaves the host under the always-encrypt policy).
class SiteSyncDatabaseEndpointTest < ActionDispatch::IntegrationTest
  PASS = "endpoint-test-passphrase"

  def setup
    SyncConfig.delete_all
    @config = SyncConfig.current
    @token  = @config.token
    # stage_encrypted_db! writes "<primary-db>.enc" next to the test DB.
    @staged = "#{SiteSync::BackupManager.primary_db_path}.enc"
    FileUtils.rm_f(@staged)
  end

  def teardown
    FileUtils.rm_f(@staged)
  end

  def auth(headers = {})
    headers.merge("Authorization" => "Bearer #{@token}")
  end

  test "rejects a request with no / wrong token" do
    post "/api/site_sync/database"
    assert_response :unauthorized

    post "/api/site_sync/database", headers: { "Authorization" => "Bearer nope" }
    assert_response :unauthorized
  end

  test "returns 204 when no backup passphrase is set (plaintext never leaves)" do
    @config.update!(backup_passphrase: nil)
    post "/api/site_sync/database", headers: auth
    assert_response :no_content
    assert_predicate response.body, :empty?
    refute File.exist?(@staged), "must not stage anything without a passphrase"
  end

  test "serves ciphertext that decrypts back to a valid SQLite database" do
    @config.update!(backup_passphrase: PASS)

    post "/api/site_sync/database", headers: auth
    assert_response :success

    blob = response.body
    assert_equal SiteSync::BackupCrypto::MAGIC, blob.byteslice(0, SiteSync::BackupCrypto::MAGIC.bytesize),
                 "response must be a Roe backup blob, not raw DB bytes"
    refute_includes blob.byteslice(0, 16).to_s, "SQLite format 3",
                    "the raw SQLite header must never appear — only ciphertext leaves"

    # Round-trip: write the served blob, decrypt with the passphrase, and
    # confirm we get a real SQLite file back.
    Dir.mktmpdir("db-endpoint") do |dir|
      enc = File.join(dir, "pulled.enc")
      out = File.join(dir, "pulled.sqlite3")
      File.binwrite(enc, blob)
      SiteSync::BackupCrypto.decrypt_file(enc, out, PASS)
      assert File.binread(out).start_with?("SQLite format 3"),
             "decrypted blob must be a valid SQLite database"
    end
  end

  test "a wrong passphrase cannot decrypt the served blob" do
    @config.update!(backup_passphrase: PASS)
    post "/api/site_sync/database", headers: auth
    assert_response :success

    Dir.mktmpdir("db-endpoint") do |dir|
      enc = File.join(dir, "pulled.enc")
      File.binwrite(enc, response.body)
      assert_raises(SiteSync::BackupCrypto::DecryptError) do
        SiteSync::BackupCrypto.decrypt_file(enc, File.join(dir, "x"), "wrong")
      end
    end
  end
end
