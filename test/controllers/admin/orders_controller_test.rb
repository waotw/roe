require "test_helper"

# The admin Orders page: lists Snipcart orders, badges buyers who are members,
# and shows an empty state (with the webhook URL to paste) when there are none.
# Anchored on data-test, not copy.
class Admin::OrdersControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }

  test "empty state shows the webhook URL to paste" do
    SnipcartOrder.delete_all
    get admin_orders_path
    assert_response :success
    assert_select "[data-test=orders-empty]"
    assert_select "[data-test=orders-webhook-url]"
    assert_select "[data-test=orders-table]", count: 0
  end

  test "lists orders with a member badge only for buyers who are members" do
    SnipcartOrder.record_completed!("token" => "t1", "email" => "member@example.com", "finalGrandTotal" => 10.0, "currency" => "usd")
    SnipcartOrder.record_completed!("token" => "t2", "email" => "stranger@example.com", "finalGrandTotal" => 20.0, "currency" => "usd")
    create(:member, email: "member@example.com", name: "M", tier: :free, status: :active)

    get admin_orders_path
    assert_response :success
    assert_select "[data-test=order-row]", count: 2
    assert_select "[data-test=order-member-badge]", count: 1
  end

  test "show renders a single order" do
    order = SnipcartOrder.record_completed!("token" => "t1", "email" => "a@b.com", "finalGrandTotal" => 10.0, "currency" => "usd")
    get admin_order_path(order)
    assert_response :success
    assert_select "[data-test=order-detail]"
  end
end
