require "test_helper"

# Members admin filters: the imported scope, and the controller flags that
# decide which filter controls render (tier only when both tiers exist,
# imported only when some member is imported, newsletter only when the feature
# is on).
class MembersAdminFiltersTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "filters-admin@example.com",
                         password: "probe-pass-123", password_confirmation: "probe-pass-123") rescue User.first
    post "/session", params: { email_address: @user.email_address, password: "probe-pass-123" }
    Member.delete_all
  end

  # ── Member.imported scope ──────────────────────────────────────────────────

  test "imported scope matches members flagged substack_imported, excludes others" do
    plain = create(:member, :active)
    imported = create(:member, :active)
    imported.update!(metadata: { "substack_imported" => true })

    assert_includes Member.imported, imported
    assert_not_includes Member.imported, plain
    # and the inverse scope is exactly complementary
    assert_includes Member.not_substack_imported, plain
    assert_not_includes Member.not_substack_imported, imported
  end

  # ── Which filter controls render ───────────────────────────────────────────

  test "tier checkboxes render only when both free and paid members exist" do
    create(:member, :active) # free only
    get "/admin/members"
    assert_no_match(/members-filter#filterByTier/, response.body)

    create(:member, :paid)   # now both
    get "/admin/members"
    assert_match(/members-filter#filterByTier/, response.body)
  end

  test "imported checkbox renders only when an imported member exists" do
    create(:member, :active)
    get "/admin/members"
    assert_no_match(/members-filter#filterByImported/, response.body)

    m = create(:member, :active); m.update!(metadata: { "substack_imported" => true })
    get "/admin/members"
    assert_match(/members-filter#filterByImported/, response.body)
  end

  test "newsletter filter renders only when newsletters are enabled" do
    create(:member, :active)
    SiteFeature.stubs(:newsletters_feature_enabled?).returns(false)
    get "/admin/members"
    assert_no_match(/filterByNewsletterStatus/, response.body)

    SiteFeature.stubs(:newsletters_feature_enabled?).returns(true)
    get "/admin/members"
    assert_match(/filterByNewsletterStatus/, response.body)
  end
end
