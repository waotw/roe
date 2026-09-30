require "test_helper"

# The admin Orders page: lists the CURRENT Snipcart mode's orders (test in test
# mode, live in live), badges buyers who are members, and shows an empty state
# with the webhook URL when there are none. Anchored on data-test, not copy.
class Admin::OrdersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    SnipcartOrder.delete_all
    SnipcartConfig.current.update!(mode: :test) # page defaults to showing test orders
  end

  def completed(token, email, mode: "test")
    SnipcartOrder.record_completed!(
      { "token" => token, "email" => email, "finalGrandTotal" => 10.0, "currency" => "usd" },
      mode: mode
    )
  end

  test "empty state shows the webhook URL to paste" do
    get admin_orders_path
    assert_response :success
    assert_select "[data-test=orders-empty]"
    assert_select "[data-test=orders-webhook-url]"
    assert_select "[data-test=orders-table]", count: 0
  end

  test "lists orders with a member badge only for buyers who are members" do
    completed("t1", "member@example.com")
    completed("t2", "stranger@example.com")
    create(:member, email: "member@example.com", name: "M", tier: :free, status: :active)

    get admin_orders_path
    assert_response :success
    assert_select "[data-test=order-row]", count: 2
    assert_select "[data-test=order-member-badge]", count: 1
  end

  test "only the current mode's orders are shown" do
    completed("t1", "a@b.com", mode: "test")
    completed("t2", "c@d.com", mode: "live")

    # In test mode, only the test order appears.
    get admin_orders_path
    assert_select "[data-test=order-row]", count: 1
    assert_select "[data-test=orders-mode]", text: /test/i

    # Switch to live mode → only the live order.
    SnipcartConfig.current.update!(mode: :live)
    get admin_orders_path
    assert_select "[data-test=order-row]", count: 1
    assert_select "[data-test=orders-mode]", text: /live/i
  end

  test "show renders a single order" do
    order = completed("t1", "a@b.com")
    get admin_order_path(order)
    assert_response :success
    assert_select "[data-test=order-detail]"
  end
end
