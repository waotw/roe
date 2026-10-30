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

  # The nightmare case: a live member's id rides along in a purge batch (a client
  # bug, a stale checkbox, a crafted request). The server must purge ONLY the
  # anonymised tombstone and leave the live member fully intact — purge is
  # irreversible, so this backstop can't depend on the client sending clean ids.
  test "purge destroys only the deleted account when a live id slips into the batch" do
    live    = create(:member, :active)
    tomb    = create(:member, :paid, paid_amount_cents: 100, paid_at: Time.current)
    tomb.anonymize!(by: :admin)
    assert_difference("Member.count", -1) do
      post bulk_purge_admin_members_path, params: { ids: [ live.id, tomb.id ] }
    end
    assert Member.exists?(live.id), "the live member is untouched"
    assert_not Member.exists?(tomb.id), "only the tombstone is purged"
  end

  test "an imported member stays filterable as imported after deletion" do
    m = create(:member, :active)
    m.update!(metadata: { "substack_imported" => true, "substack_imported_at" => "2024-01-01" })
    m.anonymize!(by: :admin)
    assert Member.imported.exists?(id: m.id), "imported origin survives anonymization"
    assert m.reload.anonymized?
  end

  # ── Invite (compose in editor, then send) ───────────────────────────────────

  test "compose_invite stashes invitable members and opens the invite editor" do
    SiteFeature.stubs(:email_feature_enabled?).returns(true)
    imported = create(:member, :active)
    imported.update!(metadata: { "substack_imported" => true })
    admin_made = create(:member, :active)
    admin_made.update!(metadata: { "admin_created" => true })

    MemberMailer.expects(:invite).never # compose doesn't send
    post compose_invite_admin_members_path, params: { ids: [ imported.id, admin_made.id ] }
    assert_redirected_to edit_admin_email_path("invite")
    assert_equal [ imported.id, admin_made.id ].sort, session[:invite_member_ids].sort
  end

  test "compose_invite carries only invitable members, not direct signups" do
    SiteFeature.stubs(:email_feature_enabled?).returns(true)
    admin_made = create(:member, :active)
    admin_made.update!(metadata: { "admin_created" => true })
    signup = create(:member, :active) # no origin marker

    post compose_invite_admin_members_path, params: { ids: [ admin_made.id, signup.id ] }
    assert_equal [ admin_made.id ], session[:invite_member_ids]
  end

  test "compose_invite with no invitable members redirects back with an alert" do
    SiteFeature.stubs(:email_feature_enabled?).returns(true)
    signup = create(:member, :active)
    post compose_invite_admin_members_path, params: { ids: [ signup.id ] }
    assert_redirected_to admin_members_path
    assert_nil session[:invite_member_ids]
  end

  test "send_invite saves the edited template and mails the stashed members" do
    SiteFeature.stubs(:email_feature_enabled?).returns(true)
    imported = create(:member, :active)
    imported.update!(metadata: { "substack_imported" => true })

    # compose first, so the session carries the selection
    post compose_invite_admin_members_path, params: { ids: [ imported.id ] }

    MemberMailer.expects(:invite).once.returns({ success: true })
    new_body = "# Custom invite\n\nHi @member_name, your password is @temp_password."
    patch send_invite_admin_members_path, params: { content: new_body }

    assert imported.reload.password_digest.present?, "a temp password was minted"
    assert_nil session[:invite_member_ids], "the stashed selection is cleared after send"
    saved = File.read(File.join(RoeSitePaths::SITE_PATH, "emails", "invite.md"))
    assert_includes saved, "Custom invite", "the edited content is saved as the draft"
  ensure
    # restore the seeded template so other tests/installs aren't affected
    ConfigGenerator.ensure_enabled_feature_files rescue nil
  end

  test "send_invite re-checks invitable and skips a now-ineligible member" do
    SiteFeature.stubs(:email_feature_enabled?).returns(true)
    m = create(:member, :active)
    m.update!(metadata: { "admin_created" => true })
    post compose_invite_admin_members_path, params: { ids: [ m.id ] }

    # the member is deleted between compose and send — send must skip it
    m.anonymize!(by: :admin)
    MemberMailer.expects(:invite).never
    patch send_invite_admin_members_path, params: { content: "@temp_password" }
  end

  test "send_invite with an expired (empty) session redirects with an alert" do
    SiteFeature.stubs(:email_feature_enabled?).returns(true)
    MemberMailer.expects(:invite).never
    patch send_invite_admin_members_path, params: { content: "x" }
    assert_redirected_to admin_members_path
  end

  test "compose_invite is refused when email is turned off" do
    SiteFeature.stubs(:email_feature_enabled?).returns(false)
    m = create(:member, :active)
    m.update!(metadata: { "admin_created" => true })
    post compose_invite_admin_members_path, params: { ids: [ m.id ] }
    assert_redirected_to admin_members_path
    assert_nil session[:invite_member_ids]
  end

  test "admin-created members are marked invitable, direct signups are not" do
    admin_made = create(:member, :active)
    admin_made.update!(metadata: { "admin_created" => true })
    signup = create(:member, :active)
    assert admin_made.invitable?
    assert_not signup.invitable?
    assert Member.invitable.exists?(admin_made.id)
    assert_not Member.invitable.exists?(signup.id)
  end

  test "a member created through the admin create action is marked admin_created" do
    assert_difference("Member.count", 1) do
      post admin_members_path, params: { member: { email: "made@example.com", name: "Made", tier: "free", status: "active" } }
    end
    m = Member.find_by(email: "made@example.com")
    assert m.admin_created?, "admin-created members carry the origin marker"
    assert m.invitable?, "so they can be sent a password invite"
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
