class Member < ApplicationRecord
  # Enums (integer-backed for SQLite performance)
  enum :tier, { free: 0, paid: 1 }, prefix: true
  enum :status, { active: 0, cancelled: 1 }, prefix: true

  # Password authentication (only for paid tier)
  has_secure_password validations: false

  # Auto-generate access token on create
  # has_secure_token :access_token

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
  before_create :generate_memorable_token

  def regenerate_token!
    update!(access_token: self.class.generate_password)
  end

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
    # Expanded word list for memorable passwords
    words = %w[
      adventure amber anchor anthem atlas autumn ballad beacon bear
      birch blossom breeze cascade cedar cherry chorus cloud coast
      compass crystal dragon eagle echo emerald explore falcon fire
      forest fountain garden golden granite harbor harmony haiku
      horizon ikigai island jade journey kintsugi lake lens
      lighthouse lion maple marble meadow melody mirror moon
      mountain nagomi oak ocean pearl petal phoenix pine prism
      quartz quest reef rhythm river ruby sake sapphire shore
      silver slate sonnet spring star stream summer sunset sushi
      thunder tiger topaz tsunami velvet voyage wabisabi willow
      wind winter wolf zen
    ]

    # 3 random words + 2 digits (e.g., "crystal-river-sunset-42")
    "#{words.sample}-#{words.sample}-#{words.sample}-#{rand(10..99)}"
  end

  # Upgrade to paid tier with Stripe payment
  def upgrade_to_paid_with_stripe!(customer_id:, payment_intent_id:, password:)
    transaction do
      update!(
        tier: :paid,
        password: password,
        password_confirmation: password,
        stripe_customer_id: customer_id,
        stripe_payment_intent_id: payment_intent_id,
        paid_at: Time.current
      )
    end
  end

  # Check if member has a Stripe customer
  def stripe_customer?
    stripe_customer_id.present?
  end

  # Get Stripe customer (if exists)
  def stripe_customer
    return nil unless stripe_customer?

    @stripe_customer ||= Stripe::Customer.retrieve(stripe_customer_id)
  rescue Stripe::InvalidRequestError
    nil
  end

  private

  def generate_memorable_token
    self.access_token ||= self.class.generate_password
  end

  def set_subscribed_at
    self.subscribed_at ||= Time.current
  end
end
