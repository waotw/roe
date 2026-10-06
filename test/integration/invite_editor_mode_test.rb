
require "test_helper"
class InviteEditorModeTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "ie@example.com", password: "probe-pass-123", password_confirmation: "probe-pass-123") rescue User.first
    post "/session", params: { email_address: @user.email_address, password: "probe-pass-123" }
    SiteFeature.stubs(:email_feature_enabled?).returns(true)
  end

  test "invite editor shows Send button and banner after compose; plain edit does not" do
    m = create(:member, :active); m.update!(metadata: { "admin_created" => true })

    # plain visit to invite template: no Send button (no invite-mode formaction)
    get edit_admin_email_path("invite")
    assert_response :success
    assert_not_includes response.body, send_invite_admin_members_path,
      "no Send button without a pending selection"

    # compose, then the editor should show invite mode
    post compose_invite_admin_members_path, params: { ids: [ m.id ] }
    get edit_admin_email_path("invite")
    assert_response :success
    # Anchor on structure, not copy (the owner edits the banner wording freely):
    # the Send button posts to send_invite and shows the member count.
    assert_includes response.body, send_invite_admin_members_path, "Send posts to send_invite"
    assert_match(/Send to\s+1\s+member/i, response.body, "Send button shows the count")
  end
end
