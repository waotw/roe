require "test_helper"

class StripeStatusTest < ActiveSupport::TestCase
  setup do
    StripeConfig.delete_all
    @sc = StripeConfig.current
  end

  def items_by_key(config = @sc)
    StripeStatus.for(config).index_by(&:key)
  end

  test "not connected when no keys are present" do
    items = items_by_key
    assert_equal :todo, items[:connection].state
    assert_match(/not connected/i, items[:connection].label)
    # webhook row omitted until keys exist
    assert_nil items[:webhook]
    # publishable is never tracked — Roe uses hosted Checkout, no Stripe.js
    assert_nil items[:publishable]
  end

  test "connected when the restricted key is present and verified" do
    StripeConfig.save_test_config("secret_key" => "sk_test_x")
    @sc.stubs(:verified_at).returns(Time.current)

    items = items_by_key(@sc)
    assert_equal :ok, items[:connection].state
    # no publishable row — it's not needed
    assert_nil items[:publishable]
  end

  test "warn state when a key is saved but not verified" do
    StripeConfig.save_test_config("secret_key" => "sk_test_x", "publishable_key" => "pk_test_x")
    @sc.stubs(:verified_at).returns(nil)
    items = items_by_key(@sc)
    assert_equal :warn, items[:connection].state
  end

  test "mode row is informational until connected, then a settled ✓" do
    # Not connected: neutral fact.
    assert_equal :info, items_by_key[:mode].state
    assert_match(/test/i, items_by_key[:mode].label)

    # Connected: ✓, matching PostmarkStatus.
    StripeConfig.save_test_config("secret_key" => "sk_test_x", "publishable_key" => "pk_test_x")
    @sc.stubs(:verified_at).returns(Time.current)
    assert_equal :ok, items_by_key(@sc)[:mode].state
  end

  test "?preview=production flips the webhook row from local-info to a prod todo" do
    StripeConfig.save_test_config("secret_key" => "sk_test_x", "publishable_key" => "pk_test_x")
    @sc.stubs(:verified_at).returns(Time.current)

    # Default (local): webhook is informational — activates on the live site.
    local = StripeStatus.for(@sc).index_by(&:key)
    assert_equal :info, local[:webhook].state

    # ui_production: reports it as a real todo (no endpoint registered yet).
    prod = StripeStatus.for(@sc, ui_production: true).index_by(&:key)
    assert_equal :todo, prod[:webhook].state
  end

  # Helper: stub the mode-agnostic members.yml payments block the price row reads.
  def stub_members_payments(price: "5.00", enabled: true)
    SiteConfig.stubs(:feature).with("members", "payments")
              .returns({ "enabled" => enabled, "price" => price })
  end

  test "price row is omitted until keys are present" do
    stub_members_payments
    assert_nil items_by_key[:price]
  end

  test "price row is omitted when payments are not enabled" do
    StripeConfig.save_test_config("secret_key" => "sk_test_x")
    @sc.stubs(:verified_at).returns(Time.current)
    stub_members_payments(enabled: false)
    assert_nil items_by_key(@sc)[:price]
  end

  test "price row tells the owner to set a price in members.yml when the amount is blank" do
    StripeConfig.save_test_config("secret_key" => "sk_test_x")
    @sc.stubs(:verified_at).returns(Time.current)
    stub_members_payments(price: "")

    item = items_by_key(@sc)[:price]
    assert_equal :todo, item.state
    assert_match(/members\.yml/i, item.detail)
    # Links to the members config editor so they can go set it.
    assert_match(%r{href="/admin/configs/members/edit"}, item.detail)
  end

  test "price row shows the members.yml amount and, when connected without a price, says click Update Mode" do
    StripeConfig.save_test_config("secret_key" => "sk_test_x")
    @sc.stubs(:verified_at).returns(Time.current)
    @sc.stubs(:current_price_id).returns(nil)
    stub_members_payments(price: "5.00")

    item = items_by_key(@sc)[:price]
    assert_equal :todo, item.state
    # Surfaces the actual amount the owner already set.
    assert_match(/members\.yml/i, item.label)
    assert_match(/5\.00/, item.label)
    # Points at the switch that regenerates the price.
    assert_match(/update mode/i, item.detail)
  end

  test "price row is ✓ once a price id exists for the current mode" do
    StripeConfig.save_test_config("secret_key" => "sk_test_x")
    @sc.stubs(:verified_at).returns(Time.current)
    @sc.stubs(:current_price_id).returns("price_123")
    stub_members_payments(price: "5.00")

    assert_equal :ok, items_by_key(@sc)[:price].state
  end
end
