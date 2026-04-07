class MailjetConfig < ApplicationRecord
  # Validations
  validates :api_key, presence: true, if: :connected?
  validates :secret_key, presence: true, if: :connected?

  # Callbacks
  before_create :set_connected_at

  # Singleton pattern
  def self.current
    first_or_create!
  end

  # Encrypted getters (decrypt when reading)
  def api_key
    decrypt(self[:api_key])
  end

  def secret_key
    decrypt(self[:secret_key])
  end

  # Encrypted setters (encrypt when writing)
  def api_key=(value)
    self[:api_key] = encrypt(value)
  end

  def secret_key=(value)
    self[:secret_key] = encrypt(value)
  end

  # Check if Mailjet is connected
  def connected?
    self[:api_key].present? && self[:secret_key].present?
  end

  # Class method for backwards compatibility
  def self.configured?
    current.connected?
  end

  # Disconnect Mailjet (clear all keys)
  def disconnect!
    update!(
      api_key: nil,
      secret_key: nil,
      connected_at: nil
    )
  end

  # Get stats from Mailjet
  def stats
    return { error: "Not configured" } unless connected?

    MailjetService.get_stats
  end

  private

  def set_connected_at
    self.connected_at ||= Time.current if self[:api_key].present?
  end

  # Encryption using Rails' secret_key_base (same as StripeConfig)
  def encryptor
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
    nil
  end
end
