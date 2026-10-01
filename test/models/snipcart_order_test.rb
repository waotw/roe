require "test_helper"

# SnipcartOrder stores orders received from Snipcart webhooks and links a buyer
# to a Roe member by email (case-insensitive), at read time so a later signup
# retroactively badges past orders.
class SnipcartOrderTest < ActiveSupport::TestCase
  def completed_payload(overrides = {})
    {
      "token"            => "abc-123",
      "email"            => "buyer@example.com",
      "billingAddress"   => { "fullName" => "Buyer Person" },
      "finalGrandTotal"  => 49.0,
      "currency"         => "usd",
      "status"           => "Processed",
      "completionDate"   => "2026-09-30T12:00:00Z"
    }.merge(overrides)
  end

  test "record_completed! stores the order with cents, name, and raw payload" do
    order = SnipcartOrder.record_completed!(completed_payload)

    assert_equal "abc-123", order.snipcart_token
    assert_equal "buyer@example.com", order.email
    assert_equal "Buyer Person", order.name
    assert_equal 4900, order.total_cents
    assert_equal 49.0, order.total
    assert_equal "usd", order.currency
    assert order.placed_at.present?
    # raw payload kept whole for future fields
    assert_equal 49.0, order.payload["finalGrandTotal"]
  end

  test "record_completed! upserts by token — a retry updates, not duplicates" do
    SnipcartOrder.record_completed!(completed_payload)
    SnipcartOrder.record_completed!(completed_payload("status" => "Shipped"))

    assert_equal 1, SnipcartOrder.where(snipcart_token: "abc-123").count
    assert_equal "Shipped", SnipcartOrder.find_by(snipcart_token: "abc-123").status
  end

  test "record_completed! ignores a payload with no token" do
    assert_nil SnipcartOrder.record_completed!({ "email" => "x@example.com" })
    assert_equal 0, SnipcartOrder.count
  end

  test "record_refund! stamps refund fields on the existing order" do
    SnipcartOrder.record_completed!(completed_payload)
    SnipcartOrder.record_refund!({
      "token" => "abc-123", "refundsAmount" => 49.0, "currency" => "usd",
      "status" => "Refunded", "modificationDate" => "2026-10-01T09:00:00Z"
    })

    order = SnipcartOrder.find_by(snipcart_token: "abc-123")
    assert order.refunded?
    assert_equal 4900, order.refunded_amount_cents
    assert_equal "Refunded", order.status
  end

  test "member matches by email case-insensitively, at read time" do
    order = SnipcartOrder.record_completed!(completed_payload("email" => "Buyer@Example.com"))
    assert_nil order.member, "no member yet"

    member = create(:member, email: "buyer@example.com", name: "Buyer", tier: :free, status: :active)
    order.reload
    assert_equal member.id, order.member&.id, "signup after purchase is matched"
    assert order.member?
  end

  test "no member match leaves member nil" do
    order = SnipcartOrder.record_completed!(completed_payload("email" => "nobody@example.com"))
    assert_nil order.member
    assert_not order.member?
  end

  test "mode is recorded and for_mode scopes to it" do
    SnipcartOrder.record_completed!(completed_payload("token" => "t-test"), mode: "test")
    SnipcartOrder.record_completed!(completed_payload("token" => "t-live"), mode: "live")

    assert_equal %w[t-test], SnipcartOrder.for_mode("test").pluck(:snipcart_token)
    assert_equal %w[t-live], SnipcartOrder.for_mode("live").pluck(:snipcart_token)
  end

  test "an unknown mode defaults to test" do
    order = SnipcartOrder.record_completed!(completed_payload, mode: "banana")
    assert order.mode_test?
  end

  test "items and sku_summary read line items from the payload" do
    order = SnipcartOrder.record_completed!(completed_payload(
      "items" => [
        { "name" => "Zine PDF", "id" => "ZINE-01", "url" => "https://shop.example.com/store/zine", "quantity" => 1 },
        { "name" => "Sticker",  "id" => "STK-02",  "url" => "https://shop.example.com/store/sticker", "quantity" => 3 }
      ]
    ))

    assert_equal 2, order.items.size
    assert_equal "Zine PDF", order.items.first.name
    assert_equal "ZINE-01", order.items.first.sku
    assert_equal "https://shop.example.com/store/zine", order.items.first.url
    assert_equal "ZINE-01 +1 more", order.sku_summary
  end

  test "sku_summary is a bare sku for a single-item order, nil for none" do
    one = SnipcartOrder.record_completed!(completed_payload("token" => "one",
      "items" => [ { "name" => "Zine", "id" => "ZINE-01" } ]))
    assert_equal "ZINE-01", one.sku_summary

    none = SnipcartOrder.record_completed!(completed_payload("token" => "none"))
    assert_empty none.items
    assert_nil none.sku_summary
  end

  test "address and phone data is stripped from the stored payload" do
    order = SnipcartOrder.record_completed!(completed_payload(
      "phone"           => "555-1234",
      "billingAddress"  => { "fullName" => "Buyer Person", "address1" => "1 Main St", "phone" => "555-1234" },
      "shippingAddress" => { "address1" => "1 Main St", "city" => "Townsville" }
    ))

    payload = order.reload.payload
    # the removed keys are gone entirely
    assert_not payload.key?("phone")
    assert_not payload.key?("billingAddress")
    assert_not payload.key?("shippingAddress")
    # a full recursive scan finds no address/phone remnants
    flat = payload.to_json.downcase
    assert_not_includes flat, "1 main st"
    assert_not_includes flat, "555-1234"
    assert_not_includes flat, "townsville"
    # non-PII we rely on is untouched
    assert_equal "usd", payload["currency"]
  end

  test "the buyer name is still captured even though billingAddress is stripped" do
    order = SnipcartOrder.record_completed!(completed_payload(
      "billingAddress" => { "fullName" => "Buyer Person", "address1" => "1 Main St" }
    ))
    assert_equal "Buyer Person", order.name           # kept in its own column
    assert_not order.reload.payload.key?("billingAddress") # but not in the payload
  end
end
