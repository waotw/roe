require "test_helper"

# The Snipcart webhook receiver: authenticated by an unguessable path token
# (SnipcartConfig#webhook_token, Postmark-style — Snipcart has no HMAC and its
# validation callback needs the secret API key Roe is dropping). Stores
# order.completed and refund.created tagged with the payload's mode, ignores
# other events, and always 200s so Snipcart doesn't retry forever.
class Webhooks::SnipcartControllerTest < ActionDispatch::IntegrationTest
  setup { @token = SnipcartConfig.current.ensure_webhook_token! }

  def post_event(event, content, token: @token, mode: "Test")
    url = token ? "/webhooks/snipcart/#{token}" : "/webhooks/snipcart"
    post url,
      params: { eventName: event, mode: mode, content: content }.to_json,
      headers: { "Content-Type" => "application/json" }
  end

  test "order.completed stores an order with its mode" do
    assert_difference "SnipcartOrder.count", 1 do
      post_event("order.completed", {
        "token" => "t1", "email" => "a@b.com",
        "finalGrandTotal" => 10.0, "currency" => "usd", "status" => "Processed"
      }, mode: "Test")
    end
    assert_response :ok
    order = SnipcartOrder.find_by(snipcart_token: "t1")
    assert_equal "a@b.com", order.email
    assert order.mode_test?
  end

  test "a live-mode order is recorded as live" do
    post_event("order.completed", { "token" => "t2", "email" => "a@b.com", "finalGrandTotal" => 5.0, "currency" => "usd" }, mode: "Live")
    assert_response :ok
    assert SnipcartOrder.find_by(snipcart_token: "t2").mode_live?
  end

  test "refund.created stamps the refund on an existing order" do
    SnipcartOrder.record_completed!({ "token" => "t1", "email" => "a@b.com", "finalGrandTotal" => 10.0, "currency" => "usd" }, mode: "test")
    post_event("refund.created", { "token" => "t1", "refundsAmount" => 10.0, "currency" => "usd", "status" => "Refunded" })
    assert_response :ok
    assert SnipcartOrder.find_by(snipcart_token: "t1").refunded?
  end

  test "an unhandled event is accepted but stores nothing" do
    assert_no_difference "SnipcartOrder.count" do
      post_event("order.status.changed", { "token" => "t9" })
    end
    assert_response :ok
  end

  # Snipcart customer-account installs fire customauth:* events alongside orders.
  # Real envelope shape (from a live Snipcart delivery): valid token, non-order
  # event → accepted and ignored, nothing stored.
  test "a real customauth customer event is accepted and ignored" do
    assert_no_difference "SnipcartOrder.count" do
      post "/webhooks/snipcart/#{@token}",
        params: {
          eventName: "customauth:customer_updated",
          mode: "Test",
          content: { "id" => "cust-1", "email" => "ben@example.com" }
        }.to_json,
        headers: { "Content-Type" => "application/json" }
    end
    assert_response :ok
  end

  test "a request with the wrong token is rejected" do
    assert_no_difference "SnipcartOrder.count" do
      post_event("order.completed", { "token" => "t1" }, token: "not-the-token")
    end
    assert_response :unauthorized
  end

  test "the tokenless legacy URL is rejected" do
    assert_no_difference "SnipcartOrder.count" do
      post_event("order.completed", { "token" => "t1" }, token: nil)
    end
    assert_response :unauthorized
  end

  test "a malformed order (no token in payload) is accepted without storing" do
    assert_no_difference "SnipcartOrder.count" do
      post_event("order.completed", { "email" => "a@b.com" })
    end
    assert_response :ok
  end
end
