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
    SnipcartOrder.record_refund!(
      "token" => "abc-123", "refundsAmount" => 49.0, "currency" => "usd",
      "status" => "Refunded", "modificationDate" => "2026-10-01T09:00:00Z"
    )

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
end
