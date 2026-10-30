require "test_helper"

# Routine password change from the member account page (password-mode sites).
# Distinct from recovery (lockout, no current password): this is the signed-in
# convenience path and requires the current password. Gated to password mode —
# email-on members have no password to rotate.
class Members::AccountPasswordChangeTest < ActionDispatch::IntegrationTest
  def setup
    super
    SiteFeature.stubs(:member_passwords_enabled?).returns(true)
    @member = create(:member,
      tier: :free, status: :active, name: "Pw User", email: "pw@example.com",
      password: "old-password-11")
  end

  def sign_in_member(member)
    get "/signin/#{member.access_token}"
  end

  test "changes the password with correct current password" do
    sign_in_member(@member)
    patch "/account/password", params: {
      current_password: "old-password-11",
      password: "new-password-22",
      password_confirmation: "new-password-22"
    }
    assert_redirected_to account_path
    assert_match(/updated/i, flash[:notice])
    assert @member.reload.authenticate("new-password-22")
  end

  test "rejects a wrong current password" do
    sign_in_member(@member)
    patch "/account/password", params: {
      current_password: "wrong-one-99",
      password: "new-password-22",
      password_confirmation: "new-password-22"
    }
    assert_redirected_to account_path
    assert_match(/current password is incorrect/i, flash[:alert])
    assert @member.reload.authenticate("old-password-11"), "password must be unchanged"
  end

  test "rejects a mismatched confirmation" do
    sign_in_member(@member)
    patch "/account/password", params: {
      current_password: "old-password-11",
      password: "new-password-22",
      password_confirmation: "different-33"
    }
    assert_redirected_to account_path
    assert_match(/must match/i, flash[:alert])
    assert @member.reload.authenticate("old-password-11"), "password must be unchanged"
  end

  test "rejects a blank new password" do
    sign_in_member(@member)
    patch "/account/password", params: {
      current_password: "old-password-11",
      password: "",
      password_confirmation: ""
    }
    assert_redirected_to account_path
    assert_match(/not be blank/i, flash[:alert])
    assert @member.reload.authenticate("old-password-11"), "password must be unchanged"
  end

  test "is a no-op redirect when passwords are disabled (email-on site)" do
    SiteFeature.unstub(:member_passwords_enabled?)
    SiteFeature.stubs(:member_passwords_enabled?).returns(false)
    sign_in_member(@member)
    patch "/account/password", params: {
      current_password: "old-password-11",
      password: "new-password-22",
      password_confirmation: "new-password-22"
    }
    assert_redirected_to account_path
    assert @member.reload.authenticate("old-password-11"), "password must be unchanged"
  end

  test "change-password form shows on the account page in password mode" do
    sign_in_member(@member)
    get "/account"
    assert_response :success
    assert_match(/change password/i, response.body)
  end
end
