require "bcrypt"
require "securerandom"

# One-time-use recovery codes for admin password reset without email
# or SSH access. Generated as 12-char alphanumeric strings, displayed
# to the user once, stored as bcrypt digests. Consumed when used (the
# `consumed_at` timestamp blocks reuse). On regeneration the user's
# whole set is replaced — see User#generate_recovery_codes!.
class RecoveryCode < ApplicationRecord
  belongs_to :user

  PLAINTEXT_LENGTH = 12

  scope :unconsumed, -> { where(consumed_at: nil) }

  def consumed?
    consumed_at.present?
  end

  def consume!
    update!(consumed_at: Time.current)
  end

  # Returns a fresh code formatted as "XXXX-XXXX-XXXX" for human
  # readability. The dashes are display only — the normalized form
  # (no dashes) is what gets hashed and compared, so users can paste
  # back with or without them.
  def self.generate_plaintext
    raw = SecureRandom.alphanumeric(PLAINTEXT_LENGTH)
    raw.scan(/.{1,4}/).join("-")
  end

  def self.normalize_plaintext(value)
    value.to_s.delete("-").strip
  end
end
