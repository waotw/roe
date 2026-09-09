# frozen_string_literal: true

require "test_helper"

# The admin showed a member's newsletter deliveries but never their money.
# It matters most after a deletion: the payments are what survives, and they're
# the reason a deleted member keeps a row at all.
class MemberPaymentsTest < ActiveSupport::TestCase
  def member(**attrs)
    Member.create!({ email: "p@example.com", name: "P", tier: :free, status: :active }.merge(attrs))
  end

  def paid_member
    member(tier: :paid, paid_at: 2.months.ago, paid_amount_cents: 5000,
           paid_currency: "usd", stripe_payment_intent_id: "pi_membership")
  end

  test "a member who never paid has no history" do
    assert_empty MemberPayments.for(member)
  end

  test "the membership payment is listed" do
    entry = MemberPayments.for(paid_member).sole

    assert_equal "Membership", entry.kind
    assert_equal "$50.00", entry.amount
    assert_equal "pi_membership", entry.reference
    assert_not entry.refunded?
  end

  test "a refund is shown against the payment, not as a separate line" do
    m = paid_member
    m.update!(refunded_at: 1.month.ago, refunded_amount_cents: 5000, refunded_currency: "usd")

    entry = MemberPayments.for(m).sole

    assert entry.refunded?
    assert_equal "$50.00", entry.refund
  end

  test "a partial refund shows the amount actually returned" do
    m = paid_member
    m.update!(refunded_at: 1.month.ago, refunded_amount_cents: 1500, refunded_currency: "usd")

    entry = MemberPayments.for(m).sole

    assert_equal "$50.00", entry.amount
    assert_equal "$15.00", entry.refund
  end

  test "donations are listed alongside the membership, newest first" do
    m = paid_member
    Donation.create!(member: m, email: m.email, amount_cents: 2500, currency: "usd",
                     created_at: 1.week.ago, stripe_payment_intent_id: "pi_d1")
    Donation.create!(member: m, email: m.email, amount_cents: 1000, currency: "usd",
                     created_at: 1.year.ago, stripe_payment_intent_id: "pi_d2")

    entries = MemberPayments.for(m)

    assert_equal %w[Donation Membership Donation], entries.map(&:kind)
    assert_equal [ "$25.00", "$50.00", "$10.00" ], entries.map(&:amount)
  end

  # An imported member can carry a payment intent with no figure against it.
  # Dropping the row would hide a real transaction.
  test "a payment with no amount is still listed" do
    m = member(stripe_payment_intent_id: "pi_imported")
    entry = MemberPayments.for(m).sole

    assert_equal "Membership", entry.kind
    assert_nil entry.amount
    assert_equal "pi_imported", entry.reference
  end

  test "non-USD amounts carry their currency" do
    m = member(paid_at: 1.day.ago, paid_amount_cents: 4200, paid_currency: "gbp")

    assert_equal "42.00 GBP", MemberPayments.for(m).sole.amount
  end

  # The whole point of keeping this after deletion.
  test "the history survives the member being deleted" do
    m = paid_member
    Donation.create!(member: m, email: m.email, amount_cents: 2500, currency: "usd",
                     stripe_payment_intent_id: "pi_d1")

    m.anonymize!
    entries = MemberPayments.for(m.reload)

    assert_equal 2, entries.size
    assert_equal "pi_membership", entries.find { |e| e.kind == "Membership" }.reference
    assert_equal [ "$25.00", "$50.00" ], entries.map(&:amount)
  end

  # Member#retained_records and this list read the same figures, so they share
  # one formatter rather than each rolling their own.
  test "the money format matches what the delete warning quotes" do
    m = paid_member

    assert_includes m.retained_records.first, MemberPayments.for(m).sole.amount
  end
end
