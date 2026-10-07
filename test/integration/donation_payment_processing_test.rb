require "test_helper"

# Donation confirmation (payment_processing) must render without raising. It
# polls for the webhook-created Donation row, looked up by stripe_session_id.
# Regression: an earlier version queried a non-existent `session_id` column,
# raising SQLite3::SQLException on every visit — so the confirmation page
# broke for every donor after a real payment.
class DonationPaymentProcessingTest < ActionDispatch::IntegrationTest
  test "renders the processing state when no donation row exists yet" do
    get donation_payment_processing_path(session_id: "cs_test_not_here_yet")
    assert_response :success
    assert_match(/processing payment/i, response.body)
  end

  test "renders with no session_id param at all (no crash)" do
    get donation_payment_processing_path
    assert_response :success
  end

  test "redirects to success once the donation row has landed" do
    Donation.create!(
      amount_cents: 1000, currency: "usd", email: "donor@example.com",
      stripe_session_id: "cs_test_landed_123"
    )
    get donation_payment_processing_path(session_id: "cs_test_landed_123")
    assert_response :success
    # Client-side redirect to the success page.
    assert_match(donation_success_path, response.body)
  end
end
