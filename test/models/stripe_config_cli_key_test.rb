require "test_helper"

# Covers the CLI-facing class methods on StripeConfig that back `roe stripe`:
# install_test_key! (paste a key in the terminal) and remove_test_key! (clear
# it again). The Stripe network calls (verify!, product/price sync) are stubbed
# — these tests assert the save/verify/remove wiring, not Stripe's API.
class StripeConfigCliKeyTest < ActiveSupport::TestCase
  setup do
    StripeConfig.delete_all
    # Keep the real stripe.yml untouched: point the file path at a tmp file.
    @tmp = Rails.root.join("tmp", "stripe_cli_test_#{SecureRandom.hex(4)}.yml").to_s
    @orig_path = StripeConfig::TEST_CONFIG_PATH
    StripeConfig.send(:remove_const, :TEST_CONFIG_PATH)
    StripeConfig.const_set(:TEST_CONFIG_PATH, @tmp)
    # These are unit tests of the save/verify/remove wiring — don't reach into
    # the real site config reload.
    SiteConfig.stubs(:sync_from_file)
  end

  teardown do
    File.delete(@tmp) if @tmp && File.exist?(@tmp)
    StripeConfig.send(:remove_const, :TEST_CONFIG_PATH)
    StripeConfig.const_set(:TEST_CONFIG_PATH, @orig_path)
  end

  # ── install_test_key! : rejection paths (no Stripe call) ──────────────────

  test "install_test_key! rejects a blank key" do
    result = StripeConfig.install_test_key!("")
    assert_not result[:ok]
    assert_equal :blank, result[:reason]
  end

  test "install_test_key! rejects a non-test key by format before any API call" do
    # If it tried to verify, this would raise (no network) — proving it bails early.
    StripeConfig.any_instance.expects(:verify!).never

    %w[sk_live_abc rk_live_abc pk_test_abc whatever].each do |bad|
      result = StripeConfig.install_test_key!(bad)
      assert_not result[:ok], "expected #{bad} to be rejected"
      assert_equal :bad_format, result[:reason]
    end
  end

  test "install_test_key! strips surrounding whitespace" do
    StripeConfig.any_instance.stubs(:verify!).returns(true)
    StripeConfig.stubs(:sync_test_price_if_missing).returns(false)

    result = StripeConfig.install_test_key!("  sk_test_spaced  \n")
    assert result[:ok]
    assert_equal "sk_test_spaced", StripeConfig.current.secret_key_test
  end

  # ── install_test_key! : verify fails ──────────────────────────────────────

  test "install_test_key! reports unverified when Stripe rejects the key" do
    StripeConfig.any_instance.stubs(:verify!).returns(false)

    result = StripeConfig.install_test_key!("sk_test_bad")
    assert_not result[:ok]
    assert_equal :unverified, result[:reason]
    # Key is still written to the file/column even though it didn't verify —
    # mirrors admin, which saves then verifies.
    assert_equal "sk_test_bad", StripeConfig.current.secret_key_test
  end

  # ── install_test_key! : success ───────────────────────────────────────────

  test "install_test_key! saves, verifies, and reports a synced price" do
    StripeConfig.any_instance.stubs(:verify!).returns(true)
    StripeConfig.stubs(:sync_test_price_if_missing).returns(true)
    # Make the price look present after sync.
    StripeConfig.any_instance.stubs(:price_id_test).returns("price_123")

    result = StripeConfig.install_test_key!("sk_test_good")
    assert result[:ok]
    assert result[:verified]
    assert result[:priced]
    assert result[:price_synced]
    assert_equal "sk_test_good", StripeConfig.current.secret_key_test
  end

  test "install_test_key! succeeds without a price (price sync skipped)" do
    StripeConfig.any_instance.stubs(:verify!).returns(true)
    StripeConfig.stubs(:sync_test_price_if_missing).returns(false)
    StripeConfig.any_instance.stubs(:price_id_test).returns(nil)

    result = StripeConfig.install_test_key!("sk_test_good")
    assert result[:ok]
    assert_not result[:priced]
    assert_not result[:price_synced]
  end

  test "install_test_key! never raises; wraps errors as a reason" do
    StripeConfig.any_instance.stubs(:verify!).raises(StandardError, "boom")

    result = StripeConfig.install_test_key!("sk_test_err")
    assert_not result[:ok]
    assert_equal :error, result[:reason]
  end

  # ── remove_test_key! ──────────────────────────────────────────────────────

  test "remove_test_key! clears the key, its ids, and verified_at" do
    StripeConfig.current.update!(
      secret_key_test: "sk_test_123",
      webhook_signing_secret_test: "whsec_123",
      product_id_test: "prod_123",
      price_id_test: "price_123",
      verified_at: Time.current
    )
    StripeConfig.save_test_config("secret_key" => "sk_test_123")

    assert StripeConfig.remove_test_key!

    sc = StripeConfig.current.reload
    assert_nil sc.secret_key_test
    assert_nil sc.webhook_signing_secret_test
    assert_nil sc.product_id_test
    assert_nil sc.price_id_test
    assert_nil sc.verified_at
    assert_equal "", StripeConfig.test_config["secret_key"].to_s
  end

  test "remove_test_key! returns false when there was no key" do
    assert_not StripeConfig.remove_test_key!
  end

  test "remove_test_key! leaves live credentials untouched" do
    StripeConfig.current.update!(
      secret_key_test: "sk_test_123",
      secret_key_live: "sk_live_keep",
      price_id_live: "price_live_keep"
    )

    StripeConfig.remove_test_key!

    sc = StripeConfig.current.reload
    assert_nil sc.secret_key_test
    assert_equal "sk_live_keep", sc.secret_key_live
    assert_equal "price_live_keep", sc.price_id_live
  end
end
