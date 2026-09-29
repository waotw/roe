require "test_helper"

# The Snipcart webhook receiver: validates X-Snipcart-RequestToken (skipped in
# test/dev — no real Snipcart callout reaches localhost), stores order.completed
# and refund.created events, ignores others, and always 200s so Snipcart doesn't
# retry forever.
class Webhooks::SnipcartControllerTest < ActionDispatch::IntegrationTest
  def post_event(event, content, headers: { "X-Snipcart-RequestToken" => "tok" })
    post snipcart_webhook_path,
      params: { eventName: event, content: content }.to_json,
      headers: headers.merge("Content-Type" => "application/json")
  end

  test "order.completed stores an order" do
    assert_difference "SnipcartOrder.count", 1 do
      post_event("order.completed", {
        "token" => "t1", "email" => "a@b.com",
        "finalGrandTotal" => 10.0, "currency" => "usd", "status" => "Processed"
      })
    end
    assert_response :ok
    assert_equal "a@b.com", SnipcartOrder.find_by(snipcart_token: "t1").email
  end

  test "refund.created stamps the refund on an existing order" do
    SnipcartOrder.record_completed!("token" => "t1", "email" => "a@b.com", "finalGrandTotal" => 10.0, "currency" => "usd")
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

  test "a request with no token is rejected" do
    assert_no_difference "SnipcartOrder.count" do
      post_event("order.completed", { "token" => "t1" }, headers: {})
    end
    assert_response :unauthorized
  end

  test "a malformed order (no token) is accepted without storing" do
    assert_no_difference "SnipcartOrder.count" do
      post_event("order.completed", { "email" => "a@b.com" })
    end
    assert_response :ok
  end
end
