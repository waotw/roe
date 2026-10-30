# frozen_string_literal: true

require "test_helper"

# The workflow this exists for: import, keep using Substack for a while, then
# run a final import before launch. That last step used to do nothing — every
# member already on live was skipped, so tier grants added since the first
# import never landed.
class SiteSync::MemberPublishTest < ActiveSupport::TestCase
  def payload(email:, tier: "paid", newsletter_status: "subscribed", imported: true, name: "Imported", status: "active")
    {
      "email" => email, "name" => name, "status" => status, "tier" => tier,
      "newsletter_status" => newsletter_status,
      "metadata" => imported ? { "substack_imported" => true } : {},
      "created_at" => 3.years.ago.iso8601, "updated_at" => Time.current.iso8601
    }
  end

  def imported_member(email:, tier: :free, **extra)
    Member.create!(email: email, name: "Existing", tier: tier,
                   metadata: { "substack_imported" => true }, **extra)
  end

  # ── the case this was built for ──────────────────────────────────────────

  test "an imported member who is now paid gets upgraded" do
    imported_member(email: "annual@example.com", tier: :free)

    result = SiteSync::MemberPublish.call([ payload(email: "annual@example.com", tier: "paid") ])

    assert_equal 1, result.updated
    assert_equal 0, result.inserted
    assert_predicate Member.find_by(email: "annual@example.com"), :tier_paid?
  end

  test "a member who isn't on live yet is still inserted" do
    result = SiteSync::MemberPublish.call([ payload(email: "new@example.com") ])

    assert_equal 1, result.inserted
    assert_predicate Member.find_by(email: "new@example.com"), :tier_paid?
  end

  # ── rule 1: an import may add, never take away ───────────────────────────

  test "a lapsed subscription never revokes paid access, and is reported" do
    # determine_tier returns free once the Substack subscription has expired.
    # Applying that would take away access the member already has.
    imported_member(email: "lapsed@example.com", tier: :paid)

    result = SiteSync::MemberPublish.call([ payload(email: "lapsed@example.com", tier: "free") ])

    assert_predicate Member.find_by(email: "lapsed@example.com"), :tier_paid?
    assert_equal [ "lapsed@example.com" ], result.follow_up["lapsed_paid"]
  end

  test "a lapsed member still has the rest of their record updated" do
    imported_member(email: "lapsed@example.com", tier: :paid, name: "Old Name")

    result = SiteSync::MemberPublish.call([ payload(email: "lapsed@example.com", tier: "free", name: "New Name") ])

    assert_equal 1, result.updated, "the record was applied; only the tier was held back"
    assert_equal 0, result.skipped
    assert_equal "New Name", Member.find_by(email: "lapsed@example.com").name
  end

  # ── rule 2: consent is never restored ────────────────────────────────────

  test "someone who unsubscribed here is not resubscribed by a CSV" do
    imported_member(email: "out@example.com", newsletter_status: :unsubscribed)

    SiteSync::MemberPublish.call([ payload(email: "out@example.com", newsletter_status: "subscribed") ])

    assert_predicate Member.find_by(email: "out@example.com"), :newsletter_status_unsubscribed?
  end

  test "an unsubscribe in the import is still applied" do
    imported_member(email: "leaving@example.com", newsletter_status: :subscribed)

    SiteSync::MemberPublish.call([ payload(email: "leaving@example.com", newsletter_status: "unsubscribed") ])

    assert_predicate Member.find_by(email: "leaving@example.com"), :newsletter_status_unsubscribed?
  end

  # ── rule 3: a deleted account is never updated or re-created ─────────────

  test "a member who deleted their own account is re-imported, deliberately" do
    # anonymize! replaces the address and email is the only key, so they arrive
    # looking like somebody new. Recognising them would mean keeping a
    # fingerprint of the address Roe just promised to destroy — and would also
    # stop anyone who deleted their account from signing up again. The CSV is
    # treated as current intent; the owner removes anyone it shouldn't carry.
    member = imported_member(email: "gone@example.com", tier: :paid)
    member.anonymize!

    result = SiteSync::MemberPublish.call([ payload(email: "gone@example.com", tier: "paid") ])

    assert_equal 1, result.inserted
    assert_empty Array(result.follow_up["deleted"])
    assert_equal 2, Member.where("email LIKE ? OR email LIKE ?", "gone@%", "deleted-%").count
  end

  test "a member deleted but still matchable by email is left alone" do
    m = imported_member(email: "bye@example.com", tier: :free)
    m.update_columns(status: Member.statuses[:deleted])

    result = SiteSync::MemberPublish.call([ payload(email: "bye@example.com", tier: "paid") ])

    assert_equal 0, result.updated
    assert_predicate Member.find_by(email: "bye@example.com"), :tier_free?
    assert_equal [ "bye@example.com" ], result.follow_up["deleted"]
  end

  # ── the activity guard ───────────────────────────────────────────────────

  test "a member who paid on live is never overwritten by an import" do
    imported_member(email: "paid-here@example.com", tier: :paid, stripe_customer_id: "cus_123")

    result = SiteSync::MemberPublish.call([ payload(email: "paid-here@example.com", tier: "free") ])

    assert_equal 0, result.updated
    assert_equal [ "paid-here@example.com" ], result.follow_up["has_activity"]
    assert_predicate Member.find_by(email: "paid-here@example.com"), :tier_paid?
  end

  test "a member who signed up here directly is never touched" do
    Member.create!(email: "organic@example.com", name: "Signed up", tier: :free)

    result = SiteSync::MemberPublish.call([ payload(email: "organic@example.com", tier: "paid") ])

    assert_equal 0, result.updated
    assert_equal [ "organic@example.com" ], result.follow_up["not_imported"]
    assert_predicate Member.find_by(email: "organic@example.com"), :tier_free?
  end

  test "a password is not treated as activity" do
    # Members sign in by emailed link. A password proves nothing either way,
    # and treating it as activity would deny someone a grant they should get.
    imported_member(email: "haspw@example.com", tier: :free, password: "whatever")

    result = SiteSync::MemberPublish.call([ payload(email: "haspw@example.com", tier: "paid") ])

    assert_equal 1, result.updated
    assert_predicate Member.find_by(email: "haspw@example.com"), :tier_paid?
  end

  # ── details that would be easy to get wrong ──────────────────────────────

  test "an update keeps this side's created_at" do
    # The sender copies its own timestamps; applying them would scramble
    # "member since" on every republish.
    original = 5.years.ago.change(usec: 0)
    member = imported_member(email: "old@example.com")
    member.update_columns(created_at: original)

    SiteSync::MemberPublish.call([ payload(email: "old@example.com") ])

    assert_equal original.to_i, Member.find_by(email: "old@example.com").created_at.to_i
  end

  test "republishing the same batch twice changes nothing the second time" do
    imported_member(email: "twice@example.com", tier: :free)
    batch = [ payload(email: "twice@example.com", tier: "paid") ]

    SiteSync::MemberPublish.call(batch)
    second = SiteSync::MemberPublish.call(batch)

    assert_equal 1, second.updated
    assert_equal 1, Member.where(email: "twice@example.com").count
  end

  test "a blank email is reported rather than raising" do
    result = SiteSync::MemberPublish.call([ payload(email: "  ") ])

    assert_equal 0, result.inserted
    assert_equal 1, result.errors.size
  end

  test "one bad record doesn't stop the rest of the batch" do
    result = SiteSync::MemberPublish.call([
      payload(email: ""), payload(email: "fine@example.com")
    ])

    assert_equal 1, result.inserted
    assert_equal 1, result.errors.size
  end
end
