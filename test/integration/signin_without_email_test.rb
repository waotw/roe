# frozen_string_literal: true

require "test_helper"

# Someone shouldn't be sent to watch an inbox for a link that was never sent.
class SigninWithoutEmailTest < ActionDispatch::IntegrationTest
  def setup
    super
    PostmarkConfig.delete_all
    @member = create(:member, email: "reader@example.com", tier: :free, status: :active)
    Rails.cache.clear
  end

  test "a site with no email says so instead of erroring" do
    FallbackMailer.any_instance.stubs(:mail).raises(Errno::ECONNREFUSED, "localhost:25")

    post "/signin", params: { member: { email: @member.email } }

    assert_redirected_to "/sign-in", "not a 500, and not on to check-email"
    assert_match(/couldn't send the sign-in email/i, flash[:alert].to_s)
  end

  # The visitor can't fix the site's mail configuration, so they're not told
  # about it.
  test "the message gives nothing away about the configuration" do
    FallbackMailer.any_instance.stubs(:mail).raises(Errno::ECONNREFUSED, "localhost:25")

    post "/signin", params: { member: { email: @member.email } }

    assert_no_match(/postmark|smtp|token/i, flash[:alert].to_s)
  end
end
