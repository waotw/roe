class PostmarkConfig < ApplicationRecord
  # Validations
  # validates :server_token, presence: true, if: :connected?

  # Callbacks
  before_create :set_connected_at
  before_create :generate_webhook_token

  # Singleton pattern
  def self.current
    first_or_create!
  end

  # Encrypted getter (decrypt when reading)
  def server_token
    decrypt(self[:server_token])
  end

  # Encrypted setter (encrypt when writing)
  def server_token=(value)
    self[:server_token] = encrypt(value)
  end

  # Check if Postmark is connected
  def connected?
    self[:server_token].present?
  end

  # Class method for backwards compatibility
  def self.configured?
    current.connected?
  end

  # Disconnect Postmark (clear token)
  def disconnect!
    update!(
      server_token: nil,
      connected_at: nil
    )
  end

  # Encrypted webhook token getter/setter
  def webhook_token
    decrypt(self[:webhook_token])
  end

  def webhook_token=(value)
    self[:webhook_token] = encrypt(value)
  end

  # Regenerate webhook token (useful if compromised)
  def regenerate_webhook_token!
    update!(webhook_token: SecureRandom.hex(32))
  end

  private

  def generate_webhook_token
    self.webhook_token ||= SecureRandom.hex(32)
  end

  def set_connected_at
    self.connected_at ||= Time.current if self[:server_token].present?
  end

  # Encryption using Rails' secret_key_base
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
