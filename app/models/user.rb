class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :recovery_codes, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  RECOVERY_CODE_COUNT = 8

  # Wipe + regenerate this user's recovery codes. Returns the plaintext
  # set (formatted with dashes) for one-time display. The plaintext is
  # never persisted — only the bcrypt digest of each normalized code.
  def generate_recovery_codes!
    plaintexts = Array.new(RECOVERY_CODE_COUNT) { RecoveryCode.generate_plaintext }
    transaction do
      recovery_codes.destroy_all
      plaintexts.each do |display|
        normalized = RecoveryCode.normalize_plaintext(display)
        recovery_codes.create!(code_digest: BCrypt::Password.create(normalized))
      end
    end
    plaintexts
  end

  # Find the unconsumed RecoveryCode whose digest matches the supplied
  # plaintext (with or without dashes). Returns nil on miss. Caller
  # consumes on success.
  def find_unconsumed_recovery_code(plaintext)
    normalized = RecoveryCode.normalize_plaintext(plaintext)
    return nil if normalized.empty?
    recovery_codes.unconsumed.find do |rc|
      begin
        BCrypt::Password.new(rc.code_digest) == normalized
      rescue BCrypt::Errors::InvalidHash
        false
      end
    end
  end
end
