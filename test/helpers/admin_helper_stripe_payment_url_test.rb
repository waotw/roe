require "test_helper"

# stripe_payment_url builds the mode-aware Stripe Dashboard deep link to a
# single payment (receipt view/resend + refund all live on that page). Dev is
# locked to test mode, so the live-mode branch is asserted via a stub.
class AdminHelperStripePaymentUrlTest < ActionView::TestCase
  include AdminHelper

  test "returns nil for a blank reference" do
    assert_nil stripe_payment_url(nil)
    assert_nil stripe_payment_url("")
  end

  test "builds a test-mode deep link" do
    StripeConfig.stubs(:current).returns(stub(mode_test?: true))
    assert_equal "https://dashboard.stripe.com/test/payments/pi_123",
                 stripe_payment_url("pi_123")
  end

  test "builds a live-mode deep link" do
    StripeConfig.stubs(:current).returns(stub(mode_test?: false))
    assert_equal "https://dashboard.stripe.com/payments/pi_456",
                 stripe_payment_url("pi_456")
  end
end
