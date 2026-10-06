require "test_helper"

# With email off (password-mode site), the 7 non-login notifications must be
# clean no-ops — never reaching the mail service and never reporting a real
# send — while magic_link and invite remain deliberate operator-triggered sends.
class MemberMailerEmailOffTest < ActiveSupport::TestCase
  setup do
    @member = create(:member, :active, email: "m@example.com", name: "Mem")
  end

  NON_LOGIN = {
    email_confirmation:    ->(m) { MemberMailer.email_confirmation(m) },
    welcome:               ->(m) { MemberMailer.welcome(m) },
    upgrade_success:       ->(m) { MemberMailer.upgrade_success(m, "pw") },
    email_changed:         ->(m) { MemberMailer.email_changed(m, "old@example.com") },
    membership_cancelled:  ->(m) { MemberMailer.membership_cancelled(m) },
    payment_failed:        ->(m) { MemberMailer.payment_failed(m) },
    account_deletion:      ->(m) { MemberMailer.account_deletion(m) }
  }.freeze

  NON_LOGIN.each do |name, call|
    test "#{name} is a no-op when email is off" do
      SiteFeature.stubs(:email_feature_enabled?).returns(false)
      PostmarkService.expects(:send_transactional_email).never
      result = call.call(@member)
      assert_equal false, result[:success], "#{name} must not report a real send"
      assert result[:skipped], "#{name} must report it was skipped"
    end
  end

  test "non-login notifications still render and attempt delivery when email is on" do
    SiteFeature.stubs(:email_feature_enabled?).returns(true)
    # Postmark not configured in test → falls back; the point is it does NOT
    # early-return as skipped, i.e. the guard lets it through when email is on.
    result = MemberMailer.welcome(@member)
    assert_nil result[:skipped], "welcome must not be skipped when email is on"
  end
end
