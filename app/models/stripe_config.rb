class StripeConfig < ApplicationRecord
  # Enum for mode (same as before)
  enum :mode, { test: 0, live: 1 }, prefix: true

  # Validations
  validates :mode, presence: true

  # Callbacks
  before_create :set_connected_at

  # Singleton pattern
  def self.current
    first_or_create!(mode: :test)
  end

  # Encrypted getters (decrypt when reading)
  def publishable_key_test
    decrypt(self[:publishable_key_test])
  end

  def secret_key_test
    decrypt(self[:secret_key_test])
  end

  def publishable_key_live
    decrypt(self[:publishable_key_live])
  end

  def secret_key_live
    decrypt(self[:secret_key_live])
  end

  def webhook_signing_secret_test
    decrypt(self[:webhook_signing_secret_test])
  end

  def webhook_signing_secret_live
    decrypt(self[:webhook_signing_secret_live])
  end

  # Encrypted setters (encrypt when writing)
  def publishable_key_test=(value)
    self[:publishable_key_test] = encrypt(value)
  end

  def secret_key_test=(value)
    self[:secret_key_test] = encrypt(value)
  end

  def publishable_key_live=(value)
    self[:publishable_key_live] = encrypt(value)
  end

  def secret_key_live=(value)
    self[:secret_key_live] = encrypt(value)
  end

  def webhook_signing_secret_test=(value)
    self[:webhook_signing_secret_test] = encrypt(value)
  end

  def webhook_signing_secret_live=(value)
    self[:webhook_signing_secret_live] = encrypt(value)
  end

  # Get the active keys based on current mode
  def current_publishable_key
    mode_test? ? publishable_key_test : publishable_key_live
  end

  def current_secret_key
    mode_test? ? secret_key_test : secret_key_live
  end

  # The webhook signing secret for the currently active mode. Used by
  # WebhooksController to verify that incoming webhook events were
  # actually sent by Stripe (not a forgery from someone who guessed the
  # endpoint URL).
  def current_webhook_signing_secret
    mode_test? ? webhook_signing_secret_test : webhook_signing_secret_live
  end

  # Options hash to pass as the trailing argument to any Stripe SDK call,
  # so each request uses the *currently configured* secret key. Without
  # this we'd fall back to the global Stripe.api_key, which is set once
  # at boot and goes stale the moment the writer switches test↔live in
  # the admin UI.
  def self.request_options
    { api_key: current.current_secret_key }
  end

  # Check if Stripe is connected
  def connected?
    publishable_key_test.present? && secret_key_test.present?
  end

  # Check if live mode is ready
  def live_mode_ready?
    publishable_key_live.present? && secret_key_live.present?
  end

  # Disconnect Stripe (clear all keys)
  def disconnect!
    update!(
      publishable_key_test: nil,
      secret_key_test: nil,
      publishable_key_live: nil,
      secret_key_live: nil,
      connected_at: nil
    )
  end

  def fetch_currency!
    return unless connected?

    # Stripe::Account.retrieve(id, opts) — id is the account ID (string)
    # or nil for the connected account. Passing `{}` here would be coerced
    # to a string for the URL path and raise TypeError.
    account = Stripe::Account.retrieve(nil, api_key: current_secret_key)
    update!(currency: account.default_currency)
  rescue Stripe::StripeError => e
    Rails.logger.error "Failed to fetch Stripe currency: #{e.message}"
    nil
  end

  # Get currency (fetch if not cached). Falls back to "usd" when the
  # cached value is blank AND the Stripe fetch returns nothing — either
  # because the API call failed (network, rate limit, bad key) or because
  # the connected Stripe account hasn't set a default currency yet. The
  # fallback isn't persisted, so a subsequent request will retry the fetch.
  def default_currency
    return currency if currency.present?
    fetch_currency!
    currency.presence || "usd"
  end

  private

  def set_connected_at
    self.connected_at ||= Time.current if publishable_key_test.present?
  end

  # Encryption using Rails' secret_key_base (already exists in every Rails app)
  def encryptor
    # Use first 32 bytes of secret_key_base as encryption key
    key = Rails.application.secret_key_base[0..31]
    ActiveSupport::MessageEncryptor.new(key)
  end

  def encrypt(value)
    return nil if value.blank?
    encryptor.encrypt_and_sign(value)
  end

  def decrypt(value)
    return nil if value.blank?
    encryptor.decrypt_and_verify(value)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    # If decryption fails, return nil (handles corrupted data gracefully)
    nil
  end
end
