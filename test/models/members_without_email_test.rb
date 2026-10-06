require "test_helper"

# Members without email: email can be turned off, and members then sign in with
# a password + recovery codes instead of a magic link. Covers the SiteFeature
# flags, the Member recovery-code API, and the password sign-in path.
class MembersWithoutEmailTest < ActiveSupport::TestCase
  # ── SiteFeature: email on/off and password mode ──────────────────────────

  test "email defaults ON when members.yml has no auth key (legacy magic-link site)" do
    SiteFeature.stubs(:members_enabled?).returns(true)
    SiteConfig.stubs(:feature).with("members", "auth.email_enabled").returns(nil)
    assert SiteFeature.email_feature_enabled?, "a missing key must read as email on"
    refute SiteFeature.member_passwords_enabled?
  end

  test "email OFF only on an explicit false, which turns on password mode" do
    SiteFeature.stubs(:members_enabled?).returns(true)
    SiteConfig.stubs(:feature).with("members", "auth.email_enabled").returns(false)
    refute SiteFeature.email_feature_enabled?
    assert SiteFeature.member_passwords_enabled?, "email off + members on => passwords"
  end

  test "explicit true keeps email on and passwords off" do
    SiteFeature.stubs(:members_enabled?).returns(true)
    SiteConfig.stubs(:feature).with("members", "auth.email_enabled").returns(true)
    assert SiteFeature.email_feature_enabled?
    refute SiteFeature.member_passwords_enabled?
  end

  test "nothing is enabled when members are off" do
    SiteFeature.stubs(:members_enabled?).returns(false)
    refute SiteFeature.email_feature_enabled?
    refute SiteFeature.member_passwords_enabled?
  end

  # ── Member recovery codes (mirror of admin User) ──────────────────────────

  test "generate_recovery_codes! returns a full set and stores only digests" do
    member = create(:member)
    codes = member.generate_recovery_codes!

    assert_equal Member::RECOVERY_CODE_COUNT, codes.length
    assert_equal Member::RECOVERY_CODE_COUNT, member.member_recovery_codes.count
    # Plaintext is never persisted — the stored digest must not equal the code.
    member.member_recovery_codes.each do |rc|
      assert_not_includes codes, rc.code_digest
    end
  end

  test "find_recovery_code matches with and without dashes, and rejects wrong codes" do
    member = create(:member)
    codes = member.generate_recovery_codes!

    assert member.find_recovery_code(codes.first), "should match the exact code"
    assert member.find_recovery_code(codes.first.delete("-")), "should match dash-stripped"
    assert_nil member.find_recovery_code("nope-nope-nope"), "wrong code must miss"
    assert_nil member.find_recovery_code(""), "blank must miss"
  end

  test "a consumed code is found but reports consumed" do
    member = create(:member)
    codes = member.generate_recovery_codes!
    member.find_recovery_code(codes.first).consume!

    found = member.find_recovery_code(codes.first)
    assert found, "a spent code is still found (to tell spent from invalid)"
    assert found.consumed?
  end

  test "regenerating replaces the previous set" do
    member = create(:member)
    old = member.generate_recovery_codes!
    member.generate_recovery_codes!

    assert_nil member.find_recovery_code(old.first), "old codes stop working after regen"
    assert_equal Member::RECOVERY_CODE_COUNT, member.member_recovery_codes.count
  end
end

# The /signin POST: magic link when email is on, password when it's off.
class MemberPasswordSigninTest < ActionDispatch::IntegrationTest
  test "password mode signs in with the right password and rejects a wrong one" do
    SiteFeature.stubs(:member_passwords_enabled?).returns(true)
    member = create(:member)
    member.update!(password: "right-pass-11", password_confirmation: "right-pass-11")

    # Needs a sign-in Page to re-render on failure.
    Page.create!(file_path: "pages/sign-in.md", metadata: { "url_name" => "sign-in", "status" => "published", "title" => "Sign In" }, content: "Sign in")

    post "/signin", params: { member: { email: member.email, password: "right-pass-11" } }
    assert_equal member.id, session[:member_id], "correct password signs in"

    delete "/signout"
    post "/signin", params: { member: { email: member.email, password: "wrong" } }
    assert_nil session[:member_id], "wrong password does not sign in"
  end

  test "password mode never sends a magic link" do
    SiteFeature.stubs(:member_passwords_enabled?).returns(true)
    member = create(:member)
    member.update!(password: "right-pass-11", password_confirmation: "right-pass-11")
    Page.create!(file_path: "pages/sign-in.md", metadata: { "url_name" => "sign-in", "status" => "published", "title" => "Sign In" }, content: "Sign in")

    MemberMailer.expects(:magic_link).never
    post "/signin", params: { member: { email: member.email, password: "right-pass-11" } }
  end
end

# Turning email off is a silent switch — it never emails members (inviting them
# is a separate, explicit step done while email still works). Guards against the
# regression where imported-but-not-launched members got blasted sign-in emails.
class ConfirmMembersPasswordsTest < ActionDispatch::IntegrationTest
  setup do
    user = User.create!(email_address: "admin-probe@example.com", password: "probe-pass-123", password_confirmation: "probe-pass-123") rescue User.first
    post "/session", params: { email_address: user.email_address, password: "probe-pass-123" }
    @fp = RoeSitePaths::SITE_PATH + "/system/features/members.yml"
    FileUtils.mkdir_p(File.dirname(@fp))
    File.write(@fp, "payments:\n  enabled: false\n") # email on (no auth key)
    SiteConfig.sync_from_file("features/members")
    create(:member, :active)
    @off = "auth:\n  email_enabled: false\npayments:\n  enabled: false\n"
  end

  teardown { File.delete(@fp) if File.exist?(@fp) }

  test "switch without acknowledgment does nothing" do
    PostmarkService.expects(:send_transactional_email).never
    post "/admin/configs/confirm_members_passwords", params: { content: @off }
    refute File.read(@fp).include?("email_enabled: false"), "email must stay on until acknowledged"
  end

  test "acknowledged switch turns email off and sends no email" do
    PostmarkService.expects(:send_transactional_email).never
    post "/admin/configs/confirm_members_passwords", params: { content: @off, acknowledge_invited: "1" }
    assert File.read(@fp).include?("email_enabled: false"), "email is now off"
  end
end
