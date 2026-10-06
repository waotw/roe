require "test_helper"

# Members admin bulk actions: delete (erase/anonymise), tier change, newsletter.
# Selection is client-side; these exercise the endpoints the controller posts to.
class MembersBulkActionsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "bulk-admin@example.com",
                         password: "probe-pass-123", password_confirmation: "probe-pass-123") rescue User.first
    post "/session", params: { email_address: @user.email_address, password: "probe-pass-123" }
    Member.delete_all
  end

  # ── Delete ─────────────────────────────────────────────────────────────────

  test "bulk delete erases members with nothing behind them" do
    a = create(:member, :active)
    b = create(:member, :active)
    assert_difference("Member.count", -2) do
      post bulk_destroy_admin_members_path, params: { ids: [ a.id, b.id ] }
    end
  end

  test "bulk delete anonymises a member with payment history, keeping the record" do
    m = create(:member, :paid, paid_amount_cents: 2500, paid_currency: "usd", paid_at: Time.current)
    assert_no_difference("Member.count") do
      post bulk_destroy_admin_members_path, params: { ids: [ m.id ] }
    end
    m.reload
    assert m.anonymized?
    assert_equal 2500, m.paid_amount_cents, "payment is kept"
    assert_not_equal "member", m.name&.downcase
  end

  test "bulk delete skips already-deleted accounts" do
    m = create(:member, :paid, paid_amount_cents: 500, paid_at: Time.current)
    m.anonymize!(by: :admin)
    assert_no_difference("Member.count") do
      post bulk_destroy_admin_members_path, params: { ids: [ m.id ] }
    end
  end

  # ── Purge (permanent, deleted accounts only) ───────────────────────────────

  test "purge permanently destroys a deleted account and its donations" do
    m = create(:member, :paid, paid_amount_cents: 999, paid_at: Time.current)
    Donation.create!(member: m, amount_cents: 500, currency: "usd",
                     email: m.email, stripe_session_id: "sess_#{SecureRandom.hex(4)}")
    m.anonymize!(by: :admin)
    assert_difference([ "Member.count", "Donation.count" ], -1) do
      post bulk_purge_admin_members_path, params: { ids: [ m.id ] }
    end
  end

  test "purge refuses a live (non-deleted) member" do
    m = create(:member, :active)
    assert_no_difference("Member.count") do
      post bulk_purge_admin_members_path, params: { ids: [ m.id ] }
    end
  end

  test "an imported member stays filterable as imported after deletion" do
    m = create(:member, :active)
    m.update!(metadata: { "substack_imported" => true, "substack_imported_at" => "2024-01-01" })
    m.anonymize!(by: :admin)
    assert Member.imported.exists?(id: m.id), "imported origin survives anonymization"
    assert m.reload.anonymized?
  end

  # ── Tier ─────────────────────────────────────────────────────────────────

  test "bulk set tier upgrades free members to paid with a password" do
    a = create(:member, :active)
    post bulk_set_tier_admin_members_path, params: { tier: "paid", ids: [ a.id ] }
    a.reload
    assert a.tier_paid?
    assert a.password_digest.present?, "an upgraded member has a password"
  end

  test "bulk set tier downgrades paid members to free and clears the password" do
    a = create(:member, :paid)
    post bulk_set_tier_admin_members_path, params: { tier: "free", ids: [ a.id ] }
    a.reload
    assert a.tier_free?
    assert_nil a.password_digest
  end

  test "bulk set tier rejects an unknown tier" do
    a = create(:member, :active)
    post bulk_set_tier_admin_members_path, params: { tier: "platinum", ids: [ a.id ] }
    assert a.reload.tier_free?, "unchanged"
  end

  # ── Newsletter ─────────────────────────────────────────────────────────────

  test "bulk newsletter unsubscribe/subscribe when newsletters enabled" do
    SiteFeature.stubs(:newsletters_feature_enabled?).returns(true)
    a = create(:member, :active) # subscribed by factory
    post bulk_newsletter_admin_members_path, params: { newsletter: "unsubscribe", ids: [ a.id ] }
    assert a.reload.newsletter_status_unsubscribed?
    post bulk_newsletter_admin_members_path, params: { newsletter: "subscribe", ids: [ a.id ] }
    assert a.reload.newsletter_status_subscribed?
  end

  test "bulk newsletter subscribe skips a bounced address" do
    SiteFeature.stubs(:newsletters_feature_enabled?).returns(true)
    a = create(:member, :active)
    a.update!(newsletter_status: :bounced)
    post bulk_newsletter_admin_members_path, params: { newsletter: "subscribe", ids: [ a.id ] }
    assert a.reload.newsletter_status_bounced?, "bounced can't be resubscribed in bulk"
  end

  test "bulk newsletter refused when newsletters are disabled" do
    SiteFeature.stubs(:newsletters_feature_enabled?).returns(false)
    a = create(:member, :active)
    post bulk_newsletter_admin_members_path, params: { newsletter: "unsubscribe", ids: [ a.id ] }
    assert a.reload.newsletter_status_subscribed?, "unchanged when newsletters off"
  end
end
