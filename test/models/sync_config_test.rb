require "test_helper"

class SyncConfigTest < ActiveSupport::TestCase
  def setup
    SyncConfig.delete_all
    @config = SyncConfig.current
  end

  test "backup_passphrase is unset by default" do
    refute @config.backup_passphrase_set?
    assert_nil @config.read_backup_passphrase
  end

  test "stores and reads a backup passphrase" do
    @config.update!(backup_passphrase: "correct horse battery staple")
    assert @config.reload.backup_passphrase_set?
    assert_equal "correct horse battery staple", @config.read_backup_passphrase
  end

  test "backup passphrase is encrypted at rest, not plaintext in the column" do
    @config.update!(backup_passphrase: "super-secret-phrase")
    raw = @config.class.connection.select_value(
      "SELECT backup_passphrase FROM sync_configs WHERE id = #{@config.id}"
    )
    refute_nil raw
    refute_includes raw.to_s, "super-secret-phrase",
                    "raw column must hold ciphertext, not the plaintext passphrase"
  end

  test "clearing the passphrase reports unset" do
    @config.update!(backup_passphrase: "x")
    assert @config.backup_passphrase_set?
    @config.update!(backup_passphrase: nil)
    refute @config.reload.backup_passphrase_set?
  end
end
