# frozen_string_literal: true

require "test_helper"

# What happens when someone reaches a limit matters more than the number.
#
# The failure to avoid is a real member locked out of their own account because
# of an address they share with strangers, or because they clicked "resend" one
# time too many. So the sign-in limit withholds the email rather than refusing
# the request, and it counts per address so a shared connection is nobody's
# problem.
class RateLimitFlowTest < ActionDispatch::IntegrationTest
  def setup
    super
    @member = create(:member, email: "reader@example.com", tier: :free, status: :active)
    Rails.cache.clear
  end

  def sign_in_attempt(email = @member.email)
    post "/signin", params: { member: { email: email } }
  end

  def emails_sent = ActionMailer::Base.deliveries.size

  test "a reader can ask for a sign-in link several times over" do
    ActionMailer::Base.deliveries.clear

    5.times { sign_in_attempt }

    assert_equal 5, emails_sent, "the default allowance is generous on purpose"
    assert_response :redirect
  end

  # The whole point. Past the limit they are still signed in as far as the flow
  # is concerned — they land where a successful request lands, and are told a
  # link is already waiting. Nothing is refused.
  test "past the limit the email stops, and the reader does not" do
    ActionMailer::Base.deliveries.clear
    6.times { sign_in_attempt }

    assert_equal 5, emails_sent, "the sixth sends nothing"
    assert_response :redirect
    assert_not_equal 429, response.status, "and it is not an error"
    assert_nil flash[:alert], "nothing has gone wrong from the reader's side"
  end

  # Counted per address, so one person hammering the form can't cost anyone
  # else their sign-in — which is the shared-IP lockout this is built to avoid.
  test "one address running out does not affect another" do
    other = create(:member, email: "someone-else@example.com", tier: :free, status: :active)
    6.times { sign_in_attempt }
    ActionMailer::Base.deliveries.clear

    sign_in_attempt(other.email)

    assert_equal 1, emails_sent, "a different address has its own allowance"
  end

  test "turning limiting off lifts it entirely" do
    RateLimits.stubs(:enabled?).returns(false)
    ActionMailer::Base.deliveries.clear

    8.times { sign_in_attempt }

    assert_equal 8, emails_sent
  end

  # A limiter that locks people out when its own backend is unwell is worse
  # than none at all.
  test "a broken cache lets everyone through" do
    Rails.cache.stubs(:increment).raises(StandardError, "cache unavailable")
    ActionMailer::Base.deliveries.clear

    8.times { sign_in_attempt }

    assert_equal 8, emails_sent, "fail open, never closed"
  end
end
