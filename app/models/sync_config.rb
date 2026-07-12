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

  # The passphrase that encrypts the SQLite DB inside full-site backups.
  # Native AR encryption (master.key) — mirrors PostmarkConfig/StripeConfig.
  # (The `token` accessors below predate this and hand-roll MessageEncryptor;
  # they're left as-is. New secrets use `encrypts`.)
  #
  # This is a *convenience* copy so scheduled/unattended backups can encrypt
  # without prompting. It is NOT the recovery key: to open a backup the admin
  # must have saved the passphrase externally (the DB copy is locked inside
  # the very backup it would unlock). See SiteSync::BackupCrypto.
  encrypts :backup_passphrase

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

  # ── Peer environment (plaintext) ───────────────────────────────────────
  #
  # What the OTHER side told us about itself over the sync handshake:
  # its Roe folder name and deploy target. Stored plaintext JSON (never
  # encrypted) because it drives restart/recovery instructions — which must
  # render even when AR encryption is broken. On production, "peer" = the
  # local machine, so peer_folder_name is the folder to `cd` into locally.

  ALLOWED_PEER_ENV_KEYS = %w[folder_name deploy_target].freeze

  def peer_env_hash
    return {} if self[:peer_env].blank?
    JSON.parse(self[:peer_env])
  rescue JSON::ParserError
    {}
  end

  def peer_folder_name
    peer_env_hash["folder_name"].presence
  end

  # "kamal" / "fly" / nil — the peer's deploy target, so we can show the
  # right restart command.
  def peer_deploy_target
    peer_env_hash["deploy_target"].presence
  end

  # Merge a peer-supplied env hash (string keys) into the stored plaintext.
  # Low-level write (update_column) — no validations/callbacks, no encryption;
  # skips the write when nothing changed so a routine exchange isn't a write.
  def merge_peer_env!(hash)
    return if hash.blank?
    cleaned = hash.stringify_keys.slice(*ALLOWED_PEER_ENV_KEYS).compact_blank
    return if cleaned.empty?

    merged = peer_env_hash.merge(cleaned)
    return if merged == peer_env_hash
    update_column(:peer_env, merged.to_json)
  end

  # ── Backup passphrase ──────────────────────────────────────────────────

  # True when a backup passphrase has been set. Uses the safe read so a
  # config restored onto a box with different AR encryption keys reports
  # "not set" instead of raising.
  def backup_passphrase_set?
    read_backup_passphrase.present?
  end

  # Decrypt the stored passphrase, returning nil (not raising) if the keys
  # can't decrypt it. This is what the backup pipeline reads to auto-encrypt.
  def read_backup_passphrase
    self[:backup_passphrase]
  rescue ActiveRecord::Encryption::Errors::Decryption => e
    Rails.logger.warn "SyncConfig#backup_passphrase decryption failed: #{e.message}"
    nil
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
