require "test_helper"

# The restore-recovery controller actions (2b): dismiss clears the flags; apply
# is production-only. The validated-apply-on-boot logic itself is covered by
# PendingRestoreTest#apply_backup_credentials!.
class SiteSyncRestoreRecoveryTest < ActionDispatch::IntegrationTest
  def setup
    sign_in_as(users(:one))
    SiteSync::RestoreCheck.clear!
  end

  def teardown
    SiteSync::RestoreCheck.clear!
  end

  test "dismiss clears the recovery flags" do
    SiteSync::RestoreCheck.flag_mismatch!
    assert SiteSync::RestoreCheck.credentials_mismatch?

    post admin_dismiss_restore_recovery_path
    assert_redirected_to admin_site_sync_path
    refute SiteSync::RestoreCheck.credentials_mismatch?, "mismatch flag cleared"
  end

  test "apply refuses outside production and stages nothing" do
    post admin_apply_backup_credentials_path
    assert_redirected_to admin_site_sync_path
    assert_match(/live site only/i, flash[:alert])
    refute SiteSync::RestoreCheck.apply_requested?, "no apply request staged in dev"
  end
end
