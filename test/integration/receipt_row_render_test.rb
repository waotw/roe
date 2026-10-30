
require "test_helper"
class ReceiptRowRenderTest < ActionDispatch::IntegrationTest
  test "paid member with no payment-intent shows the Stripe fallback, no Stripe call" do
    m = create(:member, tier: :paid, status: :active, name: "Paid", email: "p@example.com")
    # no stripe_payment_intent_id → stripe_receipt_url returns nil BEFORE any API call
    Stripe::PaymentIntent.expects(:retrieve).never
    sign_in_member(m)
    get "/account"
    assert_response :success
    assert_match(/Receipt emailed by Stripe/i, response.body)
  end

  test "paid member with a payment-intent renders a receipt link" do
    m = create(:member, tier: :paid, status: :active, name: "Paid", email: "p2@example.com")
    m.update_column(:stripe_payment_intent_id, "pi_test_123")
    fake_charge = Struct.new(:receipt_url).new("https://pay.stripe.com/receipts/abc")
    fake_pi = Struct.new(:latest_charge).new(fake_charge)
    Stripe::PaymentIntent.stubs(:retrieve).returns(fake_pi)
    sign_in_member(m)
    get "/account"
    assert_response :success
    assert_match(%r{https://pay\.stripe\.com/receipts/abc}, response.body)
    assert_match(/View receipt/i, response.body)
  end

  # Stripe being slow or down must not take the account page with it. The
  # lookup is rescued, so a StripeError just means no link — the page still
  # renders 200 and falls back to the "emailed by Stripe" text.
  test "paid member still sees the page when Stripe is unreachable (link hidden)" do
    m = create(:member, tier: :paid, status: :active, name: "Paid", email: "p3@example.com")
    m.update_column(:stripe_payment_intent_id, "pi_test_down")
    Stripe::PaymentIntent.stubs(:retrieve).raises(Stripe::APIConnectionError.new("timeout"))
    sign_in_member(m)
    get "/account"
    assert_response :success
    assert_match(/Receipt emailed by Stripe/i, response.body)
    assert_no_match(/pay\.stripe\.com\/receipts/, response.body)
  end
end
