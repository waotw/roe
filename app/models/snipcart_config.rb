class SnipcartConfig < ApplicationRecord
  # Enum for mode
  enum :mode, { test: 0, live: 1 }, prefix: true

  # Validations
  validates :mode, presence: true

  # Callbacks
  before_create :set_connected_at
  before_save :set_connected_at_on_first_key

  # Singleton pattern
  def self.current
    first_or_create!(mode: :test)
  end

  # Encrypted getters (decrypt when reading)
  def api_key_test
    decrypt(self[:api_key_test])
  end

  def api_key_live
    decrypt(self[:api_key_live])
  end

  # Encrypted setters (encrypt when writing)
  def api_key_test=(value)
    self[:api_key_test] = encrypt(value)
  end

  def api_key_live=(value)
    self[:api_key_live] = encrypt(value)
  end

  # Get the active API key based on current mode
  def current_api_key
    mode_test? ? api_key_test : api_key_live
  end

  # Check if Snipcart is connected
  def connected?
    api_key_test.present?
  end

  # Check if live mode is ready
  def live_mode_ready?
    api_key_live.present?
  end

  # Disconnect Snipcart (clear all keys)
  def disconnect!
    update!(
      api_key_test: nil,
      api_key_live: nil,
      connected_at: nil
    )
  end

  # Get store settings from store.yml
  # Get store settings from store.yml
  def currency
    SiteConfig.feature('store', 'currency') || 'usd'
  end

  def default_domain
    SiteConfig.feature('store', 'default_domain')
  end

  def load_strategy
    SiteConfig.feature('store', 'snipcart.load_strategy') || 'on-user-interaction'
  end

  def modal_style
    SiteConfig.feature('store', 'snipcart.modal_style') || 'side'
  end

  private

  def set_connected_at
    self.connected_at ||= Time.current if api_key_test.present?
  end

  def set_connected_at_on_first_key
    self.connected_at = Time.current if connected_at.nil? && (api_key_test.present? || api_key_live.present?)
  end

  # Encryption using Rails' secret_key_base
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
