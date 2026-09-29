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
    test_config["publishable_key"].presence || safe_encrypted_read(:publishable_key_test)
  end

  def secret_key_test
    test_config["secret_key"].presence || safe_encrypted_read(:secret_key_test)
  end

  def webhook_signing_secret_test
    test_config["webhook_signing_secret"].presence || safe_encrypted_read(:webhook_signing_secret_test)
  end

  # ── Live key accessors (DB only) ─────────────────────────────────────────

  def publishable_key_live
    safe_encrypted_read(:publishable_key_live)
  end

  def secret_key_live
    safe_encrypted_read(:secret_key_live)
  end

  def webhook_signing_secret_live
    safe_encrypted_read(:webhook_signing_secret_live)
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

  # Product/price IDs are mode-specific (a test-mode ID is invalid for a live
  # key), so they're stored per mode like the keys. current_* picks the active
  # mode's ID; the writer stores into the active mode's slot.
  def current_product_id
    mode_test? ? product_id_test : product_id_live
  end

  def current_price_id
    mode_test? ? price_id_test : price_id_live
  end

  def store_product_and_price!(product_id:, price_id:)
    if mode_test?
      update!(product_id_test: product_id, price_id_test: price_id)
    else
      update!(product_id_live: product_id, price_id_live: price_id)
    end
  end

  # Store a signing secret captured from StripeWebhookSetup into the column
  # for the current mode. Test-mode secrets also live in the plaintext
  # stripe.yml (Site Sync carries them, same as the other test keys); live
  # secrets are DB-only and production-only. Mirrors how the rest of the
  # config splits test vs. live.
  def store_webhook_signing_secret!(secret)
    return false if secret.to_s.strip.empty?

    if mode_test?
      cfg = self.class.test_config.merge("webhook_signing_secret" => secret)
      self.class.save_test_config(cfg)
      update!(webhook_signing_secret_test: secret)
    else
      update!(webhook_signing_secret_live: secret)
    end
    true
  end

  # Read-only registration check for the current mode's webhook endpoint —
  # proves it's registered at Roe's URL, not that events flow. Any API
  # failure reads as "not configured"; never raises. Mirrors
  # PostmarkConfig#webhook_configured?.
  def webhook_configured?(url)
    return false if current_secret_key.blank? || url.to_s.strip.empty?

    StripeWebhookSetup.new(current_secret_key).endpoint_registered?(url)
  rescue StandardError
    false
  end

  def self.request_options
    { api_key: current.current_secret_key }
  end

  # ── Connection status ────────────────────────────────────────────────────

  # Keys present for current mode. Roe uses hosted Stripe Checkout (server-side
  # redirect), never Stripe.js, so the publishable key is not required — only the
  # secret/restricted key, which every API call needs.
  def keys_present?
    current_secret_key.present?
  end

  # Verified = keys present AND last API check succeeded
  def connected?
    keys_present? && verified_at.present?
  end

  def live_mode_ready?
    secret_key_live.present?
  end

  # ── API verification ─────────────────────────────────────────────────────

  # Makes a live API call to confirm keys are valid.
  # Writes verified_at on success, clears it on failure.
  # Called on key save and from the verify controller action.
  def verify!
    return false unless keys_present?

    # Verify against WebhookEndpoint.list — a light authenticated call whose
    # scope (Webhook Endpoints: Write) Roe *always* requires for setup. This
    # deliberately does NOT depend on the Accounts scope: currency detection
    # uses Account.retrieve, but that's best-effort (falls back to usd), so a
    # fumbled Accounts permission gives a wrong-currency note, not a key that
    # won't verify. The scope that gates verification is the one the feature
    # can't work without anyway.
    Stripe.api_key = current_secret_key
    Stripe::WebhookEndpoint.list(limit: 1)
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
      product_id_test: nil,
      product_id_live: nil,
      price_id_test: nil,
      price_id_live: nil,
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
    SiteFile.read_yaml(TEST_CONFIG_PATH)["test"] || {}
  rescue => e
    Rails.logger.error "Failed to load Stripe test config: #{e.message}"
    {}
  end

  def self.save_test_config(config_data)
    FileUtils.mkdir_p(File.dirname(TEST_CONFIG_PATH))
    SiteFile.write(TEST_CONFIG_PATH, { "test" => config_data }.to_yaml.sub(/\A---\s*\n/, ""))
  end

  def self.clear_test_config
    File.delete(TEST_CONFIG_PATH) if File.exist?(TEST_CONFIG_PATH)
  end

  # ── Decryption-failure tracking ──────────────────────────────────────────

  def decryption_errors
    @decryption_errors ||= Set.new
  end

  def decryption_failed?
    decryption_errors.any?
  end

  private

  def test_config
    self.class.test_config
  end

  def safe_encrypted_read(attr)
    self[attr]
  rescue ActiveRecord::Encryption::Errors::Decryption => e
    Rails.logger.warn "#{self.class.name}##{attr} decryption failed: #{e.message}"
    decryption_errors << attr
    nil
  end

  def set_connected_at
    self.connected_at ||= Time.current if keys_present?
  end
end
