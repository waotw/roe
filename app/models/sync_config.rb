# Holds the cross-environment exchange config: a shared bearer token
# (must match on both sides) and the peer URL (only used on dev —
# production never initiates).
#
# Singleton. Auto-generates a token on first access so the admin UI
# can show it and the user can copy it to the other side without
# clicking through a "create" step first.
#
# Token is encrypted using the same MessageEncryptor pattern as
# PostmarkConfig — keyed off Rails.application.secret_key_base, which
# is derived from RAILS_MASTER_KEY in production.
class SyncConfig < ApplicationRecord
  before_create :generate_token

  def self.current
    first_or_create!
  end

  # Encrypted getter (decrypt when reading)
  def token
    decrypt(self[:token])
  end

  # Encrypted setter (encrypt when writing)
  def token=(value)
    self[:token] = encrypt(value)
  end

  def configured?
    token.present?
  end

  def regenerate_token!
    update!(token: SecureRandom.hex(32))
  end

  private

  def generate_token
    # Goes through the encrypting setter
    self.token ||= SecureRandom.hex(32)
  end

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
