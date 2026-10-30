# frozen_string_literal: true

require "test_helper"

# The member show page gains a Store History section when the member has Snipcart
# orders matched by email (case-insensitive). It's absent when they have none,
# and it links to the order detail page. Anchored on data-test, not copy.
class Admin::MemberStoreHistoryTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    SnipcartConfig.current.update!(mode: :test)
    @member = create(:member, email: "buyer@example.com", name: "Buyer", tier: :free, status: :active)
  end

  test "no Store History section when the member has no orders" do
    get admin_member_path(@member)
    assert_response :success
    assert_select "[data-test=member-store-history]", count: 0
  end

  test "Store History lists the member's orders, matched case-insensitively" do
    SnipcartOrder.record_completed!({
      "token" => "o1", "email" => "Buyer@Example.com",
      "finalGrandTotal" => 42.0, "currency" => "usd", "status" => "Processed"
    }, mode: "test")

    get admin_member_path(@member)
    assert_response :success
    assert_select "[data-test=member-store-history]"
    assert_select "[data-test=member-order-row]", count: 1
    assert_select "[data-test=member-store-test-badge]" # test mode → badged
    assert_select "a[href=?]", admin_order_path(SnipcartOrder.find_by(snipcart_token: "o1"))
  end

  test "no test-mode badge on the store history in live mode" do
    SnipcartConfig.current.update!(mode: :live)
    SnipcartOrder.record_completed!({
      "token" => "o1", "email" => "Buyer@Example.com", "finalGrandTotal" => 42.0, "currency" => "usd"
    }, mode: "live")

    get admin_member_path(@member)
    assert_response :success
    assert_select "[data-test=member-store-history]"
    assert_select "[data-test=member-store-test-badge]", count: 0
  end

  test "another member's orders don't appear here" do
    SnipcartOrder.record_completed!({
      "token" => "o2", "email" => "someone-else@example.com",
      "finalGrandTotal" => 10.0, "currency" => "usd"
    }, mode: "test")

    get admin_member_path(@member)
    assert_response :success
    assert_select "[data-test=member-store-history]", count: 0
  end
end
