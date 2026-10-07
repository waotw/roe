require "test_helper"

# Member password reset via a recovery code (email-off sites), focused on the
# post-reset behaviour: an active member is signed straight in (they already
# proved possession of a valid code AND set a new password), while a member
# who isn't active is bounced to sign-in instead of landing in a session.
class Members::RecoveryResetSignInTest < ActionDispatch::IntegrationTest
  def setup
    super
    SiteFeature.stubs(:member_passwords_enabled?).returns(true)
    # The create action renders the recover-account Page on failure; seed it so
    # a rejected path can render instead of 500-ing.
    unless Page.where("json_extract(metadata, '$.url_name') = ?", "recover-account").exists?
      create(:page, content: "Reset your password with a recovery code.",
             metadata: { "title" => "Recover account", "url_name" => "recover-account", "status" => "published" })
    end
  end

  test "a valid reset signs an active member straight in" do
    member = create(:member, status: :active, email: "r@example.com", name: "R")
    codes  = member.generate_recovery_codes!

    post "/recover-account", params: {
      email: "r@example.com",
      recovery_code: codes.first,
      password: "brand-new-pass-1",
      password_confirmation: "brand-new-pass-1"
    }

    assert_redirected_to root_path
    assert_match(/signed in/i, flash[:notice])
    assert member.reload.authenticate("brand-new-pass-1"), "password updated"
    assert_equal 1, member.member_recovery_codes.where.not(consumed_at: nil).count, "exactly one code consumed"

    # Prove the session actually carries: a members-only page loads without
    # bouncing to sign-in.
    get "/account"
    assert_response :success
  end

  test "reset works but does NOT sign in a cancelled member" do
    member = create(:member, :cancelled, email: "c@example.com", name: "C")
    codes  = member.generate_recovery_codes!

    post "/recover-account", params: {
      email: "c@example.com",
      recovery_code: codes.first,
      password: "brand-new-pass-2",
      password_confirmation: "brand-new-pass-2"
    }

    assert_redirected_to "/sign-in"
    assert member.reload.authenticate("brand-new-pass-2"), "password still updated"

    # Not signed in: the members-only page bounces.
    get "/account"
    assert_response :redirect
  end
end
