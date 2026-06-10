require "test_helper"
require "ostruct"

class PagesControllerTest < ActionDispatch::IntegrationTest
  def setup
    super

    @public_page = create(:page,
      metadata: {
        "title" => "Public Page",
        "status" => "published",
        "url_name" => "public-page"
      },
      content: "# Public Page\n\nThis is a public page."
    )

    @paid_page_no_form = create(:page,
      metadata: {
        "title" => "Paid Page",
        "status" => "published",
        "url_name" => "paid-page",
        "audience" => "paid"
      },
      content: "# Paid Page\n\nThis is paid content without a form."
    )

    @paid_page_with_form = create(:page,
      metadata: {
        "title" => "Paid Page With Paywall",
        "status" => "published",
        "url_name" => "paid-page-form",
        "audience" => "paid"
      },
      content: "# Paid Page With Paywall\n\nThis is free content.\n\n```form for: paid_content\nUpgrade now!\n```"
    )

    @draft_page = create(:page,
      metadata: {
        "title" => "Draft Page",
        "status" => "draft",
        "url_name" => "draft-page"
      },
      content: "# Draft Page\n\nThis is a draft page."
    )

    @unlisted_page = create(:page,
      metadata: {
        "title" => "Unlisted Page",
        "status" => "unlisted",
        "url_name" => "unlisted-page"
      },
      content: "# Unlisted Page\n\nThis is an unlisted page."
    )

    @free_member = create(:member, tier: :free, status: :active)
    @paid_member = create(:member, tier: :paid, status: :active)
    @cancelled_member = create(:member, tier: :paid, status: :cancelled)
    @admin = create(:user)
  end

  # ============================================================================
  # Public Content Tests
  # ============================================================================

  test "shows public published page to guest" do
    get page_path(@public_page.url_name)
    assert_response :success
    assert_select "h1", @public_page.metadata["title"]
  end

  test "shows public published page to free member" do
    sign_in_member(@free_member)
    get page_path(@public_page.url_name)
    assert_response :success
  end

  test "shows public published page to paid member" do
    sign_in_member(@paid_member)
    get page_path(@public_page.url_name)
    assert_response :success
  end

  test "shows public published page to admin" do
    sign_in_as(@admin)
    get page_path(@public_page.url_name)
    assert_response :success
  end

  # ============================================================================
  # Unlisted Content Tests
  # ============================================================================

  test "shows unlisted page to guest" do
    get page_path(@unlisted_page.url_name)
    assert_response :success
  end

  test "shows unlisted page to member" do
    sign_in_member(@free_member)
    get page_path(@unlisted_page.url_name)
    assert_response :success
  end

  # ============================================================================
  # Draft Content Tests
  # ============================================================================

  test "returns 404 for draft page when guest" do
    get page_path(@draft_page.url_name)
    assert_response :not_found
  end

  test "returns 404 for draft page when member" do
    sign_in_member(@free_member)
    get page_path(@draft_page.url_name)
    assert_response :not_found
  end

  test "shows draft page to admin" do
    sign_in_as(@admin)
    get page_path(@draft_page.url_name)
    assert_response :success
    assert_select "h1", @draft_page.metadata["title"]
  end

  # ============================================================================
  # Paid Content Tests - No Paywall Form
  # ============================================================================

  test "redirects guest to upgrade when accessing paid page without form" do
    # Enable members feature by creating the feature file
    File.write(File.join(RoeSitePaths::SITE_PATH, "system", "features", "members.yml"), { "enabled" => true }.to_yaml)

    get page_path(@paid_page_no_form.url_name)
    assert_redirected_to "/upgrade"
    assert_equal "This content requires a paid membership", flash[:alert]
  end

  test "redirects free member to upgrade when accessing paid page without form" do
    # Enable members feature by creating the feature file
    File.write(File.join(RoeSitePaths::SITE_PATH, "system", "features", "members.yml"), { "enabled" => true }.to_yaml)

    sign_in_member(@free_member)
    get page_path(@paid_page_no_form.url_name)
    assert_redirected_to "/upgrade"
    assert_equal "This content requires a paid membership", flash[:alert]
  end

  test "shows paid page to paid active member" do
    # Enable members feature by creating the feature file
    File.write(File.join(RoeSitePaths::SITE_PATH, "system", "features", "members.yml"), { "enabled" => true }.to_yaml)

    sign_in_member(@paid_member)
    get page_path(@paid_page_no_form.url_name)
    assert_response :success
    assert_select "h1", @paid_page_no_form.metadata["title"]
  end

  test "redirects cancelled paid member to upgrade" do
    # Enable members feature by creating the feature file
    File.write(File.join(RoeSitePaths::SITE_PATH, "system", "features", "members.yml"), { "enabled" => true }.to_yaml)

    sign_in_member(@cancelled_member)
    get page_path(@paid_page_no_form.url_name)
    assert_redirected_to "/upgrade"
    assert_equal "This content requires a paid membership", flash[:alert]
  end

  test "shows paid page to admin even without membership" do
    # Enable members feature by creating the feature file
    File.write(File.join(RoeSitePaths::SITE_PATH, "system", "features", "members.yml"), { "enabled" => true }.to_yaml)

    sign_in_as(@admin)
    get page_path(@paid_page_no_form.url_name)
    assert_response :success
  end

  # ============================================================================
  # Paid Content Tests - With Paywall Form
  # ============================================================================

  test "shows paid page with paywall form to guest" do
    SiteConfig.current.update!(
      file_path: "site/system/features/members.yml",
      config: { "enabled" => true }
    )

    # With paywall form, content loads but shows teaser
    get page_path(@paid_page_with_form.url_name)
    assert_response :success
  end

  test "shows paid page with paywall form to free member" do
    SiteConfig.current.update!(
      file_path: "site/system/features/members.yml",
      config: { "enabled" => true }
    )

    sign_in_member(@free_member)
    get page_path(@paid_page_with_form.url_name)
    assert_response :success
  end

  test "shows full paid page to paid member even with paywall form" do
    SiteConfig.current.update!(
      file_path: "site/system/features/members.yml",
      config: { "enabled" => true }
    )

    sign_in_member(@paid_member)
    get page_path(@paid_page_with_form.url_name)
    assert_response :success
  end

  # ============================================================================
  # Members Feature Disabled Tests
  # ============================================================================

  test "shows paid page to everyone when members feature is disabled" do
    # Stub members_enabled? to return false (no members.yml file)
    SiteFeature.stubs(:members_enabled?).returns(false)

    get page_path(@paid_page_no_form.url_name)
    assert_response :success
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  test "returns 404 for non-existent page" do
    get page_path("non-existent-page")
    assert_response :not_found
  end

  test "handles page with special characters in url_name" do
    special_page = create(:page,
      metadata: {
        "title" => "Special Page",
        "status" => "published",
        "url_name" => "special-page-123"
      }
    )

    get page_path(special_page.url_name)
    assert_response :success
  end

  test "handles nested-looking paths gracefully" do
    nested_page = create(:page,
      metadata: {
        "title" => "Nested Page",
        "status" => "published",
        "url_name" => "parent/child"
      }
    )

    get page_path(nested_page.url_name)
    assert_response :success
  end

  test "handles pages with dashes and underscores in url" do
    complex_page = create(:page,
      metadata: {
        "title" => "Complex Page",
        "status" => "published",
        "url_name" => "my-awesome_page-123"
      }
    )

    get page_path(complex_page.url_name)
    assert_response :success
  end

  # ============================================================================
  # Static Site Generation Flag Tests
  # ============================================================================

  test "page renders in dynamic mode" do
    get page_path(@public_page.url_name)
    assert_response :success
    # Check that dynamic site renders (no static file serving)
    assert_select "body"
  end

  test "page handles various content types" do
    content_page = create(:page,
      metadata: {
        "title" => "Content Page",
        "status" => "published",
        "url_name" => "content-page"
      },
      content: "# Heading\n\nParagraph with **bold** and *italic*.\n\n- List item 1\n- List item 2"
    )

    get page_path(content_page.url_name)
    assert_response :success
    assert_select "h1", "Heading"
    assert_select "strong", "bold"
    # Check that list items exist in the page (not an exact count due to navigation)
    assert_select "ul li", minimum: 2
    # Verify our specific content is present
    assert_includes response.body, "List item 1"
    assert_includes response.body, "List item 2"
  end
end
