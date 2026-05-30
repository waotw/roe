class StripeConfig < ApplicationRecord
  TEST_CONFIG_PATH = File.join(RoeSitePaths::SITE_PATH, "system", "integrations", "stripe.yml")

  enum :mode, { test: 0, live: 1 }, prefix: true

  validates :mode, presence: true

  before_create :set_connected_at

  # AR Encryption — uses master.key, no custom encrypt/decrypt needed
  encrypts :publishable_key_test
  encrypts :secret_key_test
  encrypts :webhook_signing_secret_test
  encrypts :publishable_key_live
  encrypts :secret_key_live
  encrypts :webhook_signing_secret_live

  # ── Singleton ────────────────────────────────────────────────────────────

  def self.current
    record = first_or_create!(mode: :test)
    # Dev is always test mode — prevent live mode from persisting locally
    record.update_column(:mode, 0) if Rails.env.development? && record.mode_live?
    record
  end

  # ── Test key accessors (file first, DB fallback) ─────────────────────────

  def publishable_key_test
    test_config["publishable_key"].presence || self[:publishable_key_test]
  end

  def secret_key_test
    test_config["secret_key"].presence || self[:secret_key_test]
  end

  def webhook_signing_secret_test
    test_config["webhook_signing_secret"].presence || self[:webhook_signing_secret_test]
  end

  # ── Live key accessors (DB only) ─────────────────────────────────────────

  def publishable_key_live
    self[:publishable_key_live]
  end

  def secret_key_live
    self[:secret_key_live]
  end

  def webhook_signing_secret_live
    self[:webhook_signing_secret_live]
  end

  # ── Active key based on mode ─────────────────────────────────────────────

  def current_publishable_key
    mode_test? ? publishable_key_test : publishable_key_live
  end

  def current_secret_key
    mode_test? ? secret_key_test : secret_key_live
  end

  def current_webhook_signing_secret
    mode_test? ? webhook_signing_secret_test : webhook_signing_secret_live
  end

  def self.request_options
    { api_key: current.current_secret_key }
  end

  # ── Connection status ────────────────────────────────────────────────────

  # Keys present for current mode
  def keys_present?
    current_publishable_key.present? && current_secret_key.present?
  end

  # Verified = keys present AND last API check succeeded
  def connected?
    keys_present? && verified_at.present?
  end

  def live_mode_ready?
    publishable_key_live.present? && secret_key_live.present?
  end

  # ── API verification ─────────────────────────────────────────────────────

  # Makes a live API call to confirm keys are valid.
  # Writes verified_at on success, clears it on failure.
  # Called on key save and from the verify controller action.
  def verify!
    return false unless keys_present?

    # Balance.retrieve is the lightest auth check — works with any valid
    # secret key without needing a connected account.
    Stripe.api_key = current_secret_key
    Stripe::Balance.retrieve
    update_column(:verified_at, Time.current)
    true
  rescue Stripe::AuthenticationError
    update_column(:verified_at, nil)
    false
  rescue => e
    Rails.logger.error "Stripe verification failed: #{e.message}"
    update_column(:verified_at, nil)
    false
  end

  # ── Disconnect ───────────────────────────────────────────────────────────

  def disconnect!
    update!(
      publishable_key_test: nil,
      secret_key_test: nil,
      publishable_key_live: nil,
      secret_key_live: nil,
      webhook_signing_secret_test: nil,
      webhook_signing_secret_live: nil,
      connected_at: nil,
      verified_at: nil
    )
    self.class.clear_test_config
  end

  # ── Currency ─────────────────────────────────────────────────────────────

  def fetch_currency!
    return unless keys_present?

    Stripe.api_key = current_secret_key
    account = Stripe::Account.retrieve
    update!(currency: account.default_currency)
  rescue Stripe::StripeError => e
    Rails.logger.error "Failed to fetch Stripe currency: #{e.message}"
    nil
  end

  def default_currency
    return currency if currency.present?
    fetch_currency!
    currency.presence || "usd"
  end

  # ── Test config file ─────────────────────────────────────────────────────

  def self.test_config
    return {} unless File.exist?(TEST_CONFIG_PATH)
    YAML.load_file(TEST_CONFIG_PATH)["test"] || {}
  rescue => e
    Rails.logger.error "Failed to load Stripe test config: #{e.message}"
    {}
  end

  def self.save_test_config(config_data)
    FileUtils.mkdir_p(File.dirname(TEST_CONFIG_PATH))
    File.write(TEST_CONFIG_PATH, { "test" => config_data }.to_yaml)
  end

  def self.clear_test_config
    File.delete(TEST_CONFIG_PATH) if File.exist?(TEST_CONFIG_PATH)
  end

  private

  def test_config
    self.class.test_config
  end

  def set_connected_at
    self.connected_at ||= Time.current if keys_present?
  end
end
