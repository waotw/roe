# frozen_string_literal: true

require "test_helper"

# With Postmark configured, the send goes to Postmark and letter_opener never
# sees it — it sits on the fallback path a configured Postmark skips. On a
# sandbox server that means the mail is recorded and never delivered, so there's
# no way to click the link without leaving the machine.
#
# A copy now goes to letter_opener in development as well. The real request
# still goes to Postmark and still shows up in Activity.
class MemberMailerPreviewTest < ActiveSupport::TestCase
  def setup
    super
    @member = create(:member, email: "reader@example.com", tier: :free, status: :active)
    PostmarkConfig.delete_all
    ActionMailer::Base.deliveries.clear
  end

  def with_postmark
    PostmarkConfig.stubs(:exists?).returns(true)
    PostmarkConfig.any_instance.stubs(:connected?).returns(true)
    PostmarkService.stubs(:send_transactional_email).returns({ success: true, message_id: "abc" })
  end

  test "a configured Postmark still gets the send" do
    with_postmark
    PostmarkService.expects(:send_transactional_email).once.returns({ success: true, message_id: "abc" })

    assert MemberMailer.magic_link(@member)[:success]
  end

  test "development also gets a local copy to open" do
    with_postmark
    Rails.env.stubs(:development?).returns(true)

    MemberMailer.magic_link(@member)

    assert_equal 1, ActionMailer::Base.deliveries.size, "letter_opener's copy"
  end

  test "no local copy outside development" do
    with_postmark
    Rails.env.stubs(:development?).returns(false)

    MemberMailer.magic_link(@member)

    assert_empty ActionMailer::Base.deliveries
  end

  # The preview is a convenience. It must never be able to fail a send that
  # Postmark already accepted.
  test "a broken preview doesn't affect the result" do
    with_postmark
    Rails.env.stubs(:development?).returns(true)
    FallbackMailer.any_instance.stubs(:mail).raises(StandardError, "no browser here")

    assert MemberMailer.magic_link(@member)[:success], "Postmark accepted it, so the send succeeded"
  end

  test "it can be turned off" do
    with_postmark
    Rails.env.stubs(:development?).returns(true)
    ENV["ROE_EMAIL_PREVIEW"] = "0"

    MemberMailer.magic_link(@member)

    assert_empty ActionMailer::Base.deliveries
  ensure
    ENV.delete("ROE_EMAIL_PREVIEW")
  end
end
