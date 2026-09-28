# frozen_string_literal: true

require "test_helper"

# When a member sign-in send is refused with 412 (account pending approval),
# MemberMailer records it on PostmarkConfig so the operator sees the reason on
# the settings page — instead of the member getting an opaque failure and the
# cause living only in a log. A later successful send clears it.
class MemberMailerApprovalCaptureTest < ActiveSupport::TestCase
  def setup
    super
    PostmarkConfig.delete_all
    @pm = PostmarkConfig.current
    @pm.update!(server_token: "tok", verified_at: Time.current)
    # MemberMailer only takes the Postmark path when connected? is true.
    PostmarkConfig.any_instance.stubs(:connected?).returns(true)
    SiteConfig.stubs(:get).returns(nil)
    SiteConfig.stubs(:get).with("author_email").returns("ben@weareontheweb.com")
    SiteConfig.stubs(:get).with("title").returns("Site")
    @member = create(:member, email: "reader@gmail.com", tier: :free, status: :active)
  end

  test "a 412 on send records the pending-approval flag" do
    PostmarkService.stubs(:send_transactional_email).returns(
      success: false, error: "pending approval, same domain only",
      error_code: PostmarkConfig::ACCOUNT_PENDING_APPROVAL
    )

    MemberMailer.magic_link(@member)

    assert PostmarkConfig.current.account_pending_approval?
  end

  test "a later successful send clears the flag" do
    PostmarkConfig.current.record_account_pending_approval!("old failure")

    PostmarkService.stubs(:send_transactional_email).returns(success: true, message_id: "m1")

    MemberMailer.magic_link(@member)

    assert_not PostmarkConfig.current.account_pending_approval?
  end
end
