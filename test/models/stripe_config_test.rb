require "test_helper"

class StripeConfigTest < ActiveSupport::TestCase
  setup do
    StripeConfig.delete_all
    @config = StripeConfig.current
  end

  # Class method: current
  test "current returns existing config or creates new one" do
    config1 = StripeConfig.current
    assert config1.persisted?
    assert_equal :test, config1.mode.to_sym

    config2 = StripeConfig.current
    assert_equal config1.id, config2.id
  end

  # Encryption/decryption
  test "encrypts and decrypts keys transparently" do
    test_key = "pk_test_12345"
    @config.publishable_key_test = test_key
    @config.save!

    @config.reload
    assert_equal test_key, @config.publishable_key_test
  end

  test "returns nil for blank encrypted values" do
    @config.publishable_key_test = nil
    @config.save!

    @config.reload
    assert_nil @config.publishable_key_test
  end

  test "handles corrupted encrypted data gracefully" do
    # Simulate corrupted data
    @config.update_column(:publishable_key_test, "invalid_encrypted_data")

    assert_nil @config.publishable_key_test
  end

  # Current keys based on mode
  test "current_publishable_key returns test key in test mode" do
    @config.update!(
      publishable_key_test: "pk_test_123",
      publishable_key_live: "pk_live_456",
      mode: :test
    )

    assert_equal "pk_test_123", @config.current_publishable_key
  end

  test "current_publishable_key returns live key in live mode" do
    @config.update!(
      publishable_key_test: "pk_test_123",
      publishable_key_live: "pk_live_456",
      mode: :live
    )

    assert_equal "pk_live_456", @config.current_publishable_key
  end

  test "current_secret_key returns test key in test mode" do
    @config.update!(
      secret_key_test: "sk_test_123",
      secret_key_live: "sk_live_456",
      mode: :test
    )

    assert_equal "sk_test_123", @config.current_secret_key
  end

  test "current_webhook_signing_secret returns correct secret based on mode" do
    @config.update!(
      webhook_signing_secret_test: "whsec_test_123",
      webhook_signing_secret_live: "whsec_live_456",
      mode: :test
    )

    assert_equal "whsec_test_123", @config.current_webhook_signing_secret
  end

  # Connection status
  test "connected? returns true when both keys present" do
    @config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123"
    )

    assert @config.connected?
  end

  test "connected? returns false when keys missing" do
    @config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: nil
    )

    assert_not @config.connected?
  end

  test "live_mode_ready? returns true when live keys present" do
    @config.update!(
      publishable_key_live: "pk_live_123",
      secret_key_live: "sk_live_123"
    )

    assert @config.live_mode_ready?
  end

  # Request options
  test "self.request_options returns hash with current secret key" do
    @config.update!(secret_key_test: "sk_test_abc123")

    options = StripeConfig.request_options
    assert_equal({ api_key: "sk_test_abc123" }, options)
  end

  # Disconnect
  test "disconnect! clears all keys and connected_at" do
    @config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123",
      publishable_key_live: "pk_live_123",
      secret_key_live: "sk_live_123",
      connected_at: Time.current
    )

    @config.disconnect!

    assert_nil @config.publishable_key_test
    assert_nil @config.secret_key_test
    assert_nil @config.publishable_key_live
    assert_nil @config.secret_key_live
    assert_nil @config.connected_at
  end

  # Default currency
  test "default_currency returns cached currency if present" do
    @config.update!(currency: "eur")
    assert_equal "eur", @config.default_currency
  end

  test "default_currency falls back to usd when blank" do
    @config.update!(currency: nil)
    assert_equal "usd", @config.default_currency
  end

  # Mode enum
  test "mode enum works correctly" do
    @config.update!(mode: :test)
    assert @config.mode_test?
    assert_not @config.mode_live?

    @config.update!(mode: :live)
    assert @config.mode_live?
    assert_not @config.mode_test?
  end

  # Callbacks
  test "sets connected_at on create when publishable_key_test present" do
    config = StripeConfig.create!(
      mode: :test,
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123"
    )

    assert_not_nil config.connected_at
  end

  test "does not set connected_at when publishable_key_test blank" do
    config = StripeConfig.create!(
      mode: :test,
      publishable_key_test: nil,
      secret_key_test: nil
    )

    assert_nil config.connected_at
  end

  # Edge cases
  test "handles special characters in keys" do
    special_key = "pk_test_abc123+/="
    @config.publishable_key_test = special_key
    @config.save!

    assert_equal special_key, @config.reload.publishable_key_test
  end

  test "handles very long keys" do
    long_key = "pk_test_" + "a" * 500
    @config.publishable_key_test = long_key
    @config.save!

    assert_equal long_key, @config.reload.publishable_key_test
  end
end
