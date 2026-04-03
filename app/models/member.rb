class Member < ApplicationRecord
  # Enums (integer-backed for SQLite performance)
  enum :tier, { free: 0, paid: 1 }, prefix: true
  enum :status, { active: 0, cancelled: 1 }, prefix: true

  # Password authentication (only for paid tier)
  has_secure_password validations: false

  # Auto-generate access token on create
  has_secure_token :access_token

  # Validations
  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :tier, presence: true
  validates :status, presence: true

  # Password required for paid tier
  validates :password, presence: true, if: -> { tier_paid? && password_digest.blank? }

  # Scopes
  scope :active, -> { where(status: :active) }
  scope :cancelled, -> { where(status: :cancelled) }
  scope :free_tier, -> { where(tier: :free) }
  scope :paid_tier, -> { where(tier: :paid) }

  # Scope for newsletter recipients based on content audience
  scope :for_newsletter, ->(audience) {
    case audience
    when "paid"
      active.paid_tier
    else
      active  # Everyone gets newsletters for public posts
    end
  }

  # Callbacks
  before_create :set_subscribed_at

  # Instance methods
  def paid?
    tier_paid?
  end

  def free?
    tier_free?
  end

  def active?
    status_active?
  end

  def cancelled?
    status_cancelled?
  end

  def can_access?(content)
    return true if content.audience == "everyone"
    paid? && active?
  end

  def cancel!
    update!(
      status: :cancelled,
      cancelled_at: Time.current
    )
  end

  def reactivate!
    update!(
      status: :active,
      cancelled_at: nil
    )
  end

  def upgrade_to_paid!(password:)
    transaction do
      update!(
        tier: :paid,
        password: password,
        password_confirmation: password
      )
    end
  end

  # Generate a readable password for manual upgrades
  def self.generate_password
    # 3 words + 2 digits (e.g., "sunset-river-moon-42")
    words = %w[sunset ocean mountain river forest moon star cloud wind fire]
    "#{words.sample}-#{words.sample}-#{words.sample}-#{rand(10..99)}"
  end

  private

  def set_subscribed_at
    self.subscribed_at ||= Time.current
  end
end
