require "bcrypt"

# One-time-use recovery codes for a MEMBER password reset when the site runs
# with email off (no magic link, no reset email). The member mirror of the
# admin RecoveryCode: same generation, normalization and consume-once rules —
# those stateless helpers are reused from RecoveryCode so the two can't drift.
#
# Separate table from the admin recovery_codes on purpose: a member is not an
# admin User, and keeping the admin lockout-recovery table untouched avoids any
# risk to the admin sign-in path.
class MemberRecoveryCode < ApplicationRecord
  belongs_to :member

  scope :unconsumed, -> { where(consumed_at: nil) }

  def consumed?
    consumed_at.present?
  end

  def consume!
    update!(consumed_at: Time.current)
  end
end
