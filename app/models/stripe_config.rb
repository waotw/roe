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

  # Get the active keys based on current mode
  def current_publishable_key
    mode_test? ? publishable_key_test : publishable_key_live
  end

  def current_secret_key
    mode_test? ? secret_key_test : secret_key_live
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

    account = Stripe::Account.retrieve
    update!(currency: account.default_currency)
  rescue Stripe::StripeError => e
    Rails.logger.error "Failed to fetch Stripe currency: #{e.message}"
    nil
  end

  # Get currency (fetch if not cached)
  def default_currency
    return currency if currency.present?
    fetch_currency!
    currency
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
