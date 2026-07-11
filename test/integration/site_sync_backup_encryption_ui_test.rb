require "test_helper"

# Renders the Site Sync page (verifying the tab restructure + new
# "Database backup encryption" card don't break the 65KB view) and
# exercises the passphrase update action.
class SiteSyncBackupEncryptionUiTest < ActionDispatch::IntegrationTest
  def setup
    @admin = users(:one)
    sign_in_as(@admin)
    SyncConfig.delete_all
  end

  test "site sync page renders with the encryption card and backups sections" do
    get admin_site_sync_path
    assert_response :success
    assert_select "h2", text: "Database backup encryption"
    # The live-sync status and the backups panel both still render.
    assert_select "[data-tabs-panel=live-sync]"
    assert_select "[data-tabs-panel=backups]"
    # In dev the card points the user at the live site (no passphrase form here).
    assert_match(/Set the backup passphrase on your live site/, response.body)
  end

  test "setting a matching passphrase enables encrypted backups" do
    patch admin_update_site_sync_backup_passphrase_path,
          params: { backup_passphrase: "hunter2hunter2", backup_passphrase_confirmation: "hunter2hunter2" }
    assert_redirected_to admin_site_sync_path
    assert SyncConfig.current.backup_passphrase_set?
    assert_equal "hunter2hunter2", SyncConfig.current.read_backup_passphrase
  end

  test "a mismatched confirmation changes nothing" do
    SyncConfig.current.update!(backup_passphrase: "original")
    patch admin_update_site_sync_backup_passphrase_path,
          params: { backup_passphrase: "typoA", backup_passphrase_confirmation: "typoB" }
    assert_redirected_to admin_site_sync_path
    assert_equal "original", SyncConfig.current.read_backup_passphrase, "mismatch must not overwrite"
  end

  test "a blank passphrase clears it" do
    SyncConfig.current.update!(backup_passphrase: "toclear")
    patch admin_update_site_sync_backup_passphrase_path,
          params: { backup_passphrase: "", backup_passphrase_confirmation: "" }
    assert_redirected_to admin_site_sync_path
    refute SyncConfig.current.backup_passphrase_set?
  end
end
