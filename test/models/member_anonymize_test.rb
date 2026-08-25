# frozen_string_literal: true

require "test_helper"

# Deleting an account erases the person and keeps the record.
#
# Not a destroy: newsletter_sends is `dependent: :destroy`, so removing the row
# would take every delivery record with it, and donations point at the member
# with no such rule and would be left dangling. Anonymising in place keeps both
# valid and keeps the money countable.
class MemberAnonymizeTest < ActiveSupport::TestCase
  def member
    Member.create!(
      email: "real@example.com", name: "Real Name", tier: :paid, status: :active,
      paid_amount_cents: 5000, paid_currency: "usd", paid_at: 1.month.ago,
      subscribed_at: 2.months.ago, stripe_customer_id: "cus_123",
      stripe_payment_intent_id: "pi_123", metadata: { "note" => "something" }
    )
  end

  # ── The person goes ────────────────────────────────────────────────────────

  test "identifying fields are cleared" do
    m = member
    m.anonymize!

    assert_equal "deleted-#{m.id}@deleted.invalid", m.email
    assert_equal "Deleted account", m.name
    assert_nil m.stripe_customer_id
    assert_nil m.password_digest
    assert_empty m.metadata
    assert m.status_deleted?
  end

  # `.invalid` is reserved by RFC 2606, so no mail can escape to it, and the id
  # keeps it unique — a constant would collide on the second deletion.
  test "two deleted accounts don't collide" do
    a, b = member, Member.create!(email: "b@example.com", name: "B", tier: :free, status: :active)

    a.anonymize!
    b.anonymize!

    assert_not_equal a.email, b.email
    assert_match(/\Adeleted-\d+@deleted\.invalid\z/, b.email)
  end

  # Deleting an account has to end their access, not just their listing.
  test "their tokens stop working" do
    m = member
    old_access, old_media = m.access_token, m.media_token

    m.anonymize!

    assert_not_equal old_access, m.access_token
    assert_not_equal old_media, m.media_token
    assert_not m.may_read_protected_media?, "a deleted member reads nothing"
  end

  test "they stop being a paid active member everywhere" do
    m = member
    m.anonymize!

    assert_not m.active?, "the gate every paid path already uses"
  end

  # Not just the flag — the scope the sender actually uses. Mailing
  # deleted-N@deleted.invalid would hard-bounce and cost the site its sending
  # reputation, so this is the one that has to hold.
  test "newsletters stop" do
    m = member
    m.anonymize!

    assert m.newsletter_status_unsubscribed?
    assert_not_includes Member.newsletter_subscribed, m
    assert_not_includes Member.newsletter_active, m
  end

  # ── The record stays ───────────────────────────────────────────────────────

  test "what the site owner needs is kept" do
    m = member
    m.anonymize!

    assert_equal 5000, m.paid_amount_cents
    assert_equal "usd", m.paid_currency
    assert m.paid_at.present?
    assert m.subscribed_at.present?
  end

  # A later refund finds the member by payment intent — clearing it would
  # break WebhooksController#handle_charge_refunded. It names a transaction,
  # not a person.
  test "a refund can still be matched afterwards" do
    m = member
    m.anonymize!

    assert_equal "pi_123", m.stripe_payment_intent_id
    assert_equal m, Member.find_by(stripe_payment_intent_id: "pi_123")
  end

  test "delivery records survive" do
    m = member
    post = Post.create!(file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "n.md"),
      content: "x", metadata: { "title" => "N", "url_name" => "n", "status" => "published" })
    NewsletterSend.create!(member: m, post: post, sent_at: Time.current)

    assert_difference -> { NewsletterSend.count }, 0 do
      m.anonymize!
    end

    assert_equal 1, m.newsletter_sends.count
  end

  # A donation stores its own email, so anonymising the member alone would
  # leave the same address behind by another route.
  test "their donations are anonymised too, and the amount is kept" do
    m = member
    Donation.create!(member: m, email: "real@example.com", amount_cents: 2000,
                     currency: "usd", stripe_payment_intent_id: "pi_donation")

    m.anonymize!

    donation = m.donations.first
    assert_equal "deleted-#{m.id}@deleted.invalid", donation.email
    assert_equal 2000, donation.amount_cents, "the money is still counted"
  end

  test "someone else's donation is untouched" do
    m = member
    other = Donation.create!(email: "other@example.com", amount_cents: 2000,
                             currency: "usd", stripe_payment_intent_id: "pi_other")

    m.anonymize!

    assert_equal "other@example.com", other.reload.email
  end
end
