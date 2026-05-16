# Stores deployment credentials encrypted at rest.
# Singleton — always use DeploySecrets.current.
#
# Currently holds the Docker registry password (for Kamal deploys).
# The Rails master key is read directly from config/master.key and
# never persisted here — it's already on disk and gitignored.
#
# On save, DeployConfigGenerator.generate_secrets! writes .kamal/secrets
# from this record + the master key file.
class DeploySecrets < ApplicationRecord
  def self.current
    first_or_create!
  end

  # Returns true when a registry password has been stored.
  # Used by the form to show "leave blank to keep" vs "paste token here".
  def registry_password_set?
    self[:registry_password].present?
  end

  # Encrypted getter
  def registry_password
    decrypt(self[:registry_password])
  end

  # Encrypted setter — only persists non-blank values.
  # Passing blank leaves the stored value untouched.
  def registry_password=(value)
    return if value.blank?
    self[:registry_password] = encrypt(value)
  end

  private

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
