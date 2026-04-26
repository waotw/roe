class Donation < ApplicationRecord
  # Per Stripe minimums for most currencies and a safety cap to deter abuse.
  # Values in cents (USD-equivalent). Configurable later if needed.
  MIN_AMOUNT_CENTS = 200       # $2.00
  MAX_AMOUNT_CENTS = 150_000   # $1,500.00

  belongs_to :member, optional: true

  validates :amount_cents, presence: true,
                           numericality: { only_integer: true,
                                           greater_than_or_equal_to: MIN_AMOUNT_CENTS,
                                           less_than_or_equal_to: MAX_AMOUNT_CENTS }
  validates :currency, presence: true
  validates :email, presence: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :stripe_session_id, uniqueness: true, allow_nil: true

  scope :by_date, -> { order(created_at: :desc) }

  def amount
    amount_cents / 100.0
  end

  def self.total_cents
    sum(:amount_cents)
  end
end
