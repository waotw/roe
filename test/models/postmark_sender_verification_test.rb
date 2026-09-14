# frozen_string_literal: true

require "test_helper"

# verify! answers "does the token work". This answers "will Postmark accept the
# address we send FROM", which is a different question with a different failure
# — and the only way to ask it is to attempt a send, because listing Sender
# Signatures needs an Account API token and Roe holds only a Server token.
class PostmarkSenderVerificationTest < ActiveSupport::TestCase
  setup do
    @config = PostmarkConfig.current
    with_site_config("author_email" => "hello@example.com", "author" => "Ben")
  end

  def postmark_returns(result)
    PostmarkService.stubs(:configured?).returns(true)
    PostmarkService.stubs(:send_transactional_email).returns(result)
  end

  test "a successful send records the address it sent from" do
    postmark_returns(success: true, message_id: "abc")

    @config.verify_sender!(to: "admin@example.com")

    assert_equal "hello@example.com", @config.reload.sender_verified_address
    assert_nil @config.sender_error
    assert_predicate @config, :sender_verified?
  end

  test "a refusal records what Postmark said and clears any verified address" do
    @config.update_columns(sender_verified_address: "hello@example.com")
    postmark_returns(success: false, error_code: 400,
                     error: "The 'From' address you supplied is not a Sender Signature")

    @config.verify_sender!(to: "admin@example.com")

    assert_nil @config.reload.sender_verified_address
    assert_match(/Sender Signature/, @config.sender_error)
    assert_predicate @config, :sender_rejected?
  end

  test "changing the author email makes it unverified on its own" do
    # The point of storing the ADDRESS rather than a status: there is no reset
    # hook to wire up, so there's nothing that can fall out of step.
    postmark_returns(success: true, message_id: "abc")
    @config.verify_sender!(to: "admin@example.com")
    assert_predicate @config, :sender_verified?

    with_site_config("author_email" => "someone-else@example.com")

    refute_predicate @config.reload, :sender_verified?
  end

  test "an old refusal says nothing about a new address" do
    @config.update_columns(sender_error: "rejected", sender_verified_address: nil)
    assert_predicate @config, :sender_rejected?

    postmark_returns(success: true, message_id: "abc")
    @config.verify_sender!(to: "admin@example.com")

    refute_predicate @config.reload, :sender_rejected?
  end

  test "with no address set there is nothing to verify and nothing is sent" do
    with_site_config({})
    PostmarkService.expects(:send_transactional_email).never

    result = @config.verify_sender!(to: "admin@example.com")

    refute result[:success]
    assert_equal SiteSender::MISSING, result[:error]
  end

  test "a real send refused for the From address is recorded too" do
    # Someone who never presses the button still gets the warning, after the
    # first member sign-in fails.
    @config.record_sender_rejection!("not a Sender Signature")

    assert_predicate @config.reload, :sender_rejected?
    assert_nil @config.sender_verified_address
  end
end
