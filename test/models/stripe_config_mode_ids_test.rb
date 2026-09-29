require "test_helper"

# Stripe product/price IDs are mode-specific: an ID minted with a test key is
# invalid for a live key. They're stored per mode so switching to live mode
# doesn't send test-mode IDs with the live key ("No such price … exists in test
# mode, but a live mode key was used").
class StripeConfigModeIdsTest < ActiveSupport::TestCase
  setup do
    StripeConfig.delete_all
    @sc = StripeConfig.current
  end

  test "current_price_id / current_product_id follow the active mode" do
    @sc.update!(
      product_id_test: "prod_test", price_id_test: "price_test",
      product_id_live: "prod_live", price_id_live: "price_live"
    )

    @sc.update!(mode: :test)
    assert_equal "price_test",  @sc.current_price_id
    assert_equal "prod_test",   @sc.current_product_id

    @sc.update!(mode: :live)
    assert_equal "price_live",  @sc.current_price_id
    assert_equal "prod_live",   @sc.current_product_id
  end

  test "store_product_and_price! writes only the active mode's slot" do
    @sc.update!(mode: :test)
    @sc.store_product_and_price!(product_id: "prod_t", price_id: "price_t")
    assert_equal "prod_t", @sc.product_id_test
    assert_nil @sc.product_id_live

    @sc.update!(mode: :live)
    @sc.store_product_and_price!(product_id: "prod_l", price_id: "price_l")
    assert_equal "prod_l", @sc.product_id_live
    # test slot untouched — the bug this prevents
    assert_equal "prod_t", @sc.product_id_test
  end

  test "current_price_id is nil for a mode that hasn't been set up" do
    @sc.update!(mode: :test, price_id_test: "price_t")
    @sc.update!(mode: :live)
    assert_nil @sc.current_price_id, "live has no price yet, even though test does"
  end

  test "disconnect! clears all per-mode product/price IDs" do
    @sc.update!(
      product_id_test: "a", price_id_test: "b",
      product_id_live: "c", price_id_live: "d"
    )
    @sc.disconnect!
    @sc.reload
    assert_nil @sc.product_id_test
    assert_nil @sc.product_id_live
    assert_nil @sc.price_id_test
    assert_nil @sc.price_id_live
  end
end
