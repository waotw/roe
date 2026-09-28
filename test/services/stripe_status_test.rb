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
end
