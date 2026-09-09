# frozen_string_literal: true

# Everything a member has paid, in one date-ordered list: the membership
# payment and any donations, each with its refund if there was one.
#
# The admin already showed a member's newsletter deliveries but never their
# money, which left the site owner reading `paid_amount_cents` off nothing at
# all. It matters most after an account is deleted — the payments are exactly
# what survives, and they're the reason a deleted member keeps a row.
#
# Membership payments live on the member (one per account, since checkout runs
# in `payment` mode and nothing recurs); donations are their own table. Both
# read the same way to whoever is looking, so they're merged here rather than
# in the view.
class MemberPayments
  Entry = Struct.new(
    :date, :kind, :amount_cents, :currency,
    :refunded_at, :refunded_amount_cents, :refunded_currency, :reference,
    keyword_init: true
  ) do
    def refunded? = refunded_at.present? || refunded_amount_cents.to_i.positive?

    def amount  = MemberPayments.money(amount_cents, currency)
    def refund  = MemberPayments.money(refunded_amount_cents, refunded_currency || currency)
  end

  def self.for(member) = new(member).all

  # One definition of what money looks like, shared with Member#retained_records
  # so the two can't drift into disagreeing about the same figure.
  def self.money(cents, currency)
    return nil unless cents.to_i.positive?

    amount = format("%.2f", cents / 100.0)
    currency.to_s.downcase == "usd" ? "$#{amount}" : "#{amount} #{currency.to_s.upcase}"
  end

  def initialize(member)
    @member = member
  end

  def all
    (membership + donations).sort_by { |e| e.date || Time.at(0) }.reverse
  end

  private

  # An imported member can carry a payment intent with no amount against it,
  # so any one of the three is enough to say a payment happened.
  def membership
    return [] if @member.paid_at.blank? &&
                 !@member.paid_amount_cents.to_i.positive? &&
                 @member.stripe_payment_intent_id.blank?

    [ Entry.new(
      date: @member.paid_at || @member.subscribed_at || @member.created_at,
      kind: "Membership",
      amount_cents: @member.paid_amount_cents,
      currency: @member.paid_currency,
      refunded_at: @member.refunded_at,
      refunded_amount_cents: @member.refunded_amount_cents,
      refunded_currency: @member.refunded_currency,
      reference: @member.stripe_payment_intent_id
    ) ]
  end

  def donations
    @member.donations.order(created_at: :desc).map do |d|
      Entry.new(
        date: d.created_at,
        kind: "Donation",
        amount_cents: d.amount_cents,
        currency: d.currency,
        refunded_at: d.refunded_at,
        refunded_amount_cents: d.refunded_amount_cents,
        refunded_currency: d.refunded_currency,
        reference: d.stripe_payment_intent_id
      )
    end
  end
end
