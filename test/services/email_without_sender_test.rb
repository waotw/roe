# frozen_string_literal: true

require "test_helper"

# Roe has no address of its own to send from. Postmark rejects any From it
# hasn't verified, so a stand-in like noreply@example.com can't rescue a send —
# it replaces "you haven't set your email address" with an opaque rejection
# about a domain nobody owns. Refusing is the useful answer.
class EmailWithoutSenderTest < ActiveSupport::TestCase
  setup { PostmarkService.stubs(:configured?).returns(true) }

  test "a transactional send refuses rather than inventing an address" do
    SiteSender.stubs(:configured?).returns(false)
    # If it got as far as HTTP, the refusal didn't happen.
    Net::HTTP.any_instance.expects(:request).never

    result = PostmarkService.send_transactional_email(
      to_email: "reader@example.com", to_name: "Reader",
      subject: "Sign in", html_content: "<p>link</p>"
    )

    refute result[:success]
    assert_equal SiteSender::MISSING, result[:error]
  end

  test "the refusal names the setting to change" do
    assert_match(/Author Email/, SiteSender::MISSING)
    assert_match(/Settings/, SiteSender::MISSING)
  end

  test "no placeholder address survives anywhere in the send paths" do
    # The bug: `|| "noreply@example.com"` meant a blank author_email produced
    # From: " <>" instead of a clear failure.
    [ "app/services/postmark_service.rb",
      "app/jobs/send_newsletter_job.rb" ].each do |file|
      source = File.read(Rails.root.join(file))
      refute_match(/noreply@example\.com/, source, "#{file} still has a stand-in From address")
    end
  end

  test "Postmark's error code is kept so an unverified sender can be told apart" do
    source = File.read(Rails.root.join("app/services/postmark_service.rb"))
    assert_match(/error_code:.*ErrorCode/, source,
                 "without the code, 'not verified' and 'malformed' look identical")
  end
end
