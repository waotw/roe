require "test_helper"

# Confirming a pending email change via the link in the confirmation email.
# The link is self-authenticating (the token is the proof), so it must work
# WITHOUT a session — opened from an email client, a phone, any browser —
# which is exactly where the old session-gated version bounced to sign-in and
# left the new address pending forever.
class Members::ConfirmEmailTest < ActionDispatch::IntegrationTest
  def setup
    super
    SiteFeature.stubs(:email_feature_enabled?).returns(true)
    @member = create(:member, status: :active, email: "old@example.com", name: "E")
    @member.pending_email = "new@example.com"
    @member.save!
    @member.generate_email_confirmation_token!
    @token = @member.reload.email_confirmation_token
  end

  test "confirms the new email from the link with NO session" do
    # No sign_in_member — simulate opening the link in a fresh browser.
    get confirm_email_path(token: @token)

    assert_redirected_to "/sign-in"
    assert_match(/confirmed/i, flash[:notice])

    @member.reload
    assert_equal "new@example.com", @member.email, "new address is now live"
    assert_nil @member.pending_email, "pending cleared"
    assert_nil @member.email_confirmation_token, "token consumed"
  end

  test "confirms and returns a signed-in member to their account" do
    sign_in_member(@member)
    get confirm_email_path(token: @token)

    assert_redirected_to account_path
    assert_match(/confirmed/i, flash[:notice])
    assert_equal "new@example.com", @member.reload.email
  end

  test "a bad token does not change the email and never 500s without a session" do
    get confirm_email_path(token: "wrong-token-00")

    assert_redirected_to "/sign-in"
    assert_match(/invalid or expired/i, flash[:alert])
    assert_equal "old@example.com", @member.reload.email, "email unchanged"
    assert_equal "new@example.com", @member.pending_email, "still pending"
  end

  test "a blank token is rejected cleanly" do
    get confirm_email_path(token: "")
    assert_redirected_to "/sign-in"
    assert_match(/invalid or expired/i, flash[:alert])
  end
end
