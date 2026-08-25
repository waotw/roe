# frozen_string_literal: true

require "test_helper"

# Delete Member in the admin. The button used to call destroy, which took the
# newsletter delivery history with it (`dependent: :destroy`) and left donations
# pointing at a row that no longer existed — still carrying the donor's real
# email. It deleted the useful part and kept the private part.
class Admin::MemberDeletionTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }

  def member(**attrs)
    Member.create!({ email: "m@example.com", name: "M", tier: :free, status: :active }.merge(attrs))
  end

  def post_for_send
    Post.create!(file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "d.md"), content: "x",
      metadata: { "title" => "D", "url_name" => "d", "status" => "published" })
  end

  # ── Nothing behind them: really gone ──────────────────────────────────────
  #
  # A spam signup shouldn't leave a permanent "Deleted account" row in the
  # members list.
  test "a member with no history is removed outright" do
    m = member

    assert_difference -> { Member.count }, -1 do
      delete admin_member_path(m)
    end

    assert_redirected_to admin_members_path
  end

  # ── Records behind them: anonymised ───────────────────────────────────────

  test "a member who was sent a newsletter is anonymised, and the send survives" do
    m = member
    NewsletterSend.create!(member: m, post: post_for_send, sent_at: Time.current)

    assert_no_difference [ -> { Member.count }, -> { NewsletterSend.count } ] do
      delete admin_member_path(m)
    end

    assert m.reload.anonymized?
    assert_equal "Deleted account", m.name
  end

  test "a member who paid is anonymised, and the payment is still readable" do
    m = member(tier: :paid, paid_at: 1.week.ago, paid_amount_cents: 5000,
               paid_currency: "usd", stripe_payment_intent_id: "pi_admin")

    assert_no_difference -> { Member.count } do
      delete admin_member_path(m)
    end

    m.reload
    assert m.anonymized?
    assert_equal 5000, m.paid_amount_cents
    assert_equal "pi_admin", m.stripe_payment_intent_id, "a later refund still matches"
  end

  # The donation row survived the old destroy, so the address survived with it.
  # Deleting a member has to reach it.
  test "a donor is anonymised, and the donation keeps its amount but not their email" do
    m = member
    d = Donation.create!(member: m, email: "m@example.com", amount_cents: 2000,
                         currency: "usd", stripe_payment_intent_id: "pi_donation")

    assert_no_difference [ -> { Member.count }, -> { Donation.count } ] do
      delete admin_member_path(m)
    end

    d.reload
    assert_equal 2000, d.amount_cents
    assert_not_equal "m@example.com", d.email
    assert_equal m.reload.id, d.member_id, "the donation still points at a real row"
  end

  # ── What the page says ────────────────────────────────────────────────────

  # "Cancelled" reads like there's nothing left, so the page has to name what's
  # actually holding the account back from being removed outright.
  test "the page names what's keeping the member from being erased" do
    m = member(tier: :paid, paid_at: Time.utc(2025, 12, 1), paid_amount_cents: 2500,
               paid_currency: "usd", status: :cancelled)
    NewsletterSend.create!(member: m, post: post_for_send, sent_at: Time.current)

    get admin_member_path(m)

    assert_match "$25.00 payment from December 2025", response.body
    assert_match "1 newsletter", response.body
  end

  # Asserts the branch, not the wording — the prose here is the site owner's to
  # edit, and pinning it turns a copy change into a red test.
  test "a member with nothing behind them is offered no Kept list" do
    get admin_member_path(member)

    assert_response :success
    assert_match "Delete Member", response.body
    assert_no_match "Kept:", response.body
  end

  # The index renders its own status badge. Nothing covered this view before,
  # and an ERB template only fails at render time.
  test "the members list shows Deleted apart from Cancelled" do
    member(email: "gone@example.com", tier: :paid, paid_at: 1.week.ago,
           paid_amount_cents: 5000).anonymize!
    member(email: "quit@example.com", status: :cancelled)

    get admin_members_path

    assert_response :success
    assert_match ">Deleted<", response.body
    assert_match ">Cancelled<", response.body
  end

  # ── After deletion, the record has to still be findable and readable ──────

  test "a deleted member is still listed, and filterable as deleted" do
    m = member(tier: :paid, paid_at: 1.week.ago, paid_amount_cents: 5000)
    m.anonymize!

    get admin_members_path
    assert_match m.reload.email, response.body, "a deleted member vanished from the list"

    get admin_members_path(status: "deleted")
    assert_match m.email, response.body, "the Deleted filter didn't find them"
  end

  # Every deleted account reads deleted-N@deleted.invalid, so the date is the
  # only handle left that says which one this is and when it happened.
  test "a deleted account is date-stamped" do
    m = member(tier: :paid, paid_at: 1.week.ago, paid_amount_cents: 5000)
    m.anonymize!

    get admin_member_path(m)

    assert_match m.reload.cancelled_at.strftime("%b %d, %Y"), response.body
  end

  # ── A deleted account is a record, not a member ───────────────────────────

  test "the controls that no longer apply are gone" do
    m = member(tier: :paid, paid_at: 1.week.ago, paid_amount_cents: 5000)
    m.anonymize!

    get admin_member_path(m)

    assert_response :success
    # By path, not by label — the explanatory copy mentions reactivating, and
    # the wording there is the site owner's to change.
    assert_no_match downgrade_to_free_admin_member_path(m), response.body
    assert_no_match upgrade_to_paid_admin_member_path(m), response.body
    assert_no_match reactivate_membership_admin_member_path(m), response.body
    assert_no_match cancel_membership_admin_member_path(m), response.body
    assert_no_match edit_admin_member_path(m), response.body

    # Regenerated on deletion, so they belong to nobody — noise on the page.
    assert_no_match m.access_token, response.body
    assert_no_match m.media_token, response.body
    assert_no_match "Access Token", response.body
  end

  test "a live member's tokens are still shown" do
    get admin_member_path(member)

    assert_match "Access Token", response.body
    assert_match "Media Token", response.body
  end

  # Hiding a button doesn't close the URL behind it. Editing would put a name
  # and address back on a row whose whole point is not having one.
  test "the actions behind those controls refuse too" do
    m = member(tier: :paid, paid_at: 1.week.ago, paid_amount_cents: 5000,
               stripe_payment_intent_id: "pi_guard")
    m.anonymize!
    deleted_email = m.reload.email

    [ [ :get, ->(x) { edit_admin_member_path(x) } ],
      [ :patch, ->(x) { upgrade_to_paid_admin_member_path(x) } ],
      [ :patch, ->(x) { downgrade_to_free_admin_member_path(x) } ],
      [ :patch, ->(x) { cancel_membership_admin_member_path(x) } ],
      [ :patch, ->(x) { reactivate_membership_admin_member_path(x) } ] ].each do |verb, path|
      send(verb, path.call(m))

      assert_redirected_to admin_member_path(m), "#{path.call(m)} wasn't refused"
    end

    patch admin_member_path(m), params: { member: { email: "back@example.com", name: "Back" } }
    assert_equal deleted_email, m.reload.email, "an edit put their address back"
    assert m.anonymized?, "the account came back from deleted"
  end

  test "the record itself stays readable" do
    m = member(tier: :paid, paid_at: 1.week.ago, paid_amount_cents: 5000)
    m.anonymize!

    get admin_member_path(m)

    assert_response :success
    assert_match "Payment History", response.body
    assert_match "Deleted", response.body
  end

  test "their payment history is still on the page after deletion" do
    m = member(tier: :paid, paid_at: 1.week.ago, paid_amount_cents: 5000,
               paid_currency: "usd", stripe_payment_intent_id: "pi_kept")
    Donation.create!(member: m, email: m.email, amount_cents: 2500, currency: "usd",
                     stripe_payment_intent_id: "pi_donation_kept")
    m.anonymize!

    get admin_member_path(m)

    assert_response :success
    assert_match "Payment History", response.body
    assert_match "$50.00", response.body
    assert_match "$25.00", response.body
    assert_match "pi_kept", response.body, "the Stripe reference a refund needs"
  end

  test "a member with no payments is told so rather than shown an empty table" do
    get admin_member_path(member)

    assert_match "Payment History", response.body
    assert_match "not made any payments", response.body
  end

  test "an already-deleted account isn't offered for deletion again" do
    m = member(tier: :paid, paid_at: 1.week.ago, paid_amount_cents: 5000)
    m.anonymize!

    get admin_member_path(m)

    assert_response :success
    assert_no_match "Delete Member", response.body
    assert_match "Account Deleted", response.body
  end
end
