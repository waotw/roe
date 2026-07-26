class Member < ApplicationRecord
  # Enums (integer-backed for SQLite performance)
  enum :tier, { free: 0, paid: 1 }, prefix: true
  enum :status, { active: 0, cancelled: 1 }, prefix: true
  enum :newsletter_status, { subscribed: 0, unsubscribed: 1, bounced: 2 }, prefix: true

  belongs_to :import, optional: true

  has_many :newsletter_sends, dependent: :destroy
  has_many :newsletters_received, through: :newsletter_sends, source: :post

  # Password authentication (only for paid tier)
  has_secure_password validations: false

  # Auto-generate access token on create
  # has_secure_token :access_token

  # Validations
  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :pending_email, uniqueness: { case_sensitive: false }, allow_nil: true
  validate :pending_email_not_taken
  validates :name, presence: true
  validates :tier, presence: true
  validates :status, presence: true

  # Password required for paid tier
  # validates :password, presence: true, if: -> { tier_paid? && password_digest.blank? }

  # Scopes
  scope :active, -> { where(status: :active) }
  scope :cancelled, -> { where(status: :cancelled) }
  scope :free_tier, -> { where(tier: :free) }
  scope :paid_tier, -> { where(tier: :paid) }
  scope :newsletter_subscribed, -> { where(newsletter_status: :subscribed) }
  scope :newsletter_unsubscribed, -> { where(newsletter_status: :unsubscribed) }
  scope :newsletter_active, -> { active.newsletter_subscribed }

  # Durable Substack-origin filter. Used by the resend filters in
  # PostsController so a Substack-imported newsletter is never re-sent to
  # members who originally received it via Substack — even if the Import
  # record gets deleted and the import_id FK is nilled.
  scope :not_substack_imported, -> {
    where("json_extract(metadata, '$.substack_imported') IS NULL OR json_extract(metadata, '$.substack_imported') = 0")
  }

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

  def generate_unsubscribe_token
    self.access_token ||= generate_memorable_token
    save if changed?
    access_token
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
      adventure akihabara amber anchor anime april army atlas
      autumn ballad beacon bear bento birch blade blossom blue
      bonsai breeze bushido california cascade castle cedar cherry
      chibi chorus cloud coast compass crystal dango diaries
      dragon dobermann dorama dozo eagle emerald explore express
      falcon fiction fire five forest fountain four futon garden
      geisha golden granite haiku hanami harbor harmony hibiki
      hikikomori hinoki horizon house ikigai inari island izakaya
      jade journey kabuki kaizen kakigori kamikaze karaoke
      kawaii killbill kiki kintsugi koi komorebi lake lens
      lighthouse lion maboroshi machete maple marble master
      matsuri meadow melody memories manga marine mirror miso
      moon mountain nagomi netsuke ninja nodachi oak ocean
      once origami otaku paper pearl petal phoenix pine
      pokemon porco prism pulpfiction quartz quest ramen
      reservoirdogs reservoir rhythm river ronin ruby sake
      sakura samurai sapphire sensei shore shuriken silver
      slate sonnet spirit spring star stream summer sumimasen
      sumo sunset sushi taiko takoyaki tanuki tatami
      tempura teru-teru-bozu thunder tiger time tofu topaz
      torii train true trueromance tsunami umami
      velvet voyage wabisabi wakaresaseya wasabi wind winter
      wolf yakuza yukata zen
    ]

    # 3 random words + 2 digits (e.g., "crystal-river-sunset-42")
    "#{words.sample}-#{words.sample}-#{words.sample}-#{rand(10..99)}"
  end

  # Upgrade to paid tier with Stripe payment. The amount snapshot is
  # optional for back-compat — older callers (and any test stubs) may
  # not pass it; the dashboard treats nil as "amount unknown".
  def upgrade_to_paid_with_stripe!(customer_id:, payment_intent_id:, password:, amount_cents: nil, currency: nil)
    transaction do
      update!(
        tier: :paid,
        password: password,
        password_confirmation: password,
        stripe_customer_id: customer_id,
        stripe_payment_intent_id: payment_intent_id,
        paid_at: Time.current,
        paid_amount_cents: amount_cents,
        paid_currency: currency
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

    @stripe_customer ||= Stripe::Customer.retrieve(stripe_customer_id, StripeConfig.request_options)
  rescue Stripe::InvalidRequestError
    nil
  end

  def generate_email_confirmation_token!
    update!(
      email_confirmation_token: self.class.generate_password,
      email_confirmation_sent_at: Time.current
    )
  end

  def confirm_email!(token)
    return false unless email_confirmation_token == token
    return false if email_confirmation_expired?

    transaction do
      update!(
        email: pending_email,
        pending_email: nil,
        email_confirmation_token: nil,
        email_confirmation_sent_at: nil
      )
    end

    true
  end

  def email_confirmation_expired?
    return false unless email_confirmation_sent_at
    email_confirmation_sent_at < 24.hours.ago
  end

  def unsubscribe_from_newsletter!
    update!(newsletter_status: "unsubscribed")
  end

  # NEWSLETTER

  def newsletter_subscribed?
    newsletter_status_subscribed?
  end

  def newsletter_unsubscribed?
    newsletter_status_unsubscribed?
  end

  def unsubscribe_from_newsletter!
    update!(newsletter_status: :unsubscribed)
  end

  def resubscribe_to_newsletter!
    update!(newsletter_status: :subscribed)
  end

  private

  def generate_memorable_token
    self.access_token ||= self.class.generate_password
  end

  def set_subscribed_at
    self.subscribed_at ||= Time.current
  end

  def pending_email_not_taken
    return if pending_email.blank?

    if Member.where.not(id: id).exists?(email: pending_email)
      errors.add(:pending_email, "is already taken")
    end
  end
end
