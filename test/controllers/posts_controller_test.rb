require "test_helper"
require "ostruct"

class PostsControllerTest < ActionDispatch::IntegrationTest
  def setup
    super

    @public_post = create(:post,
      metadata: {
        "title" => "Public Post",
        "status" => "published",
        "date" => "2024-01-01",
        "audience" => "everyone"
      },
      content: "# Public Post\n\nThis is a public post."
    )

    @paid_post_no_form = create(:post,
      metadata: {
        "title" => "Paid Post",
        "status" => "published",
        "date" => "2024-01-02",
        "audience" => "paid"
      },
      content: "# Paid Post\n\nThis is paid content without a form."
    )

    @paid_post_with_form = create(:post,
      metadata: {
        "title" => "Paid Post With Paywall",
        "status" => "published",
        "date" => "2024-01-03",
        "audience" => "paid"
      },
      content: "# Paid Post With Paywall\n\nThis is free content.\n\n```form for: paid_content\nUpgrade now!\n```"
    )

    @draft_post = create(:post,
      metadata: {
        "title" => "Draft Post",
        "status" => "draft",
        "date" => "2024-01-04"
      },
      content: "# Draft Post\n\nThis is a draft post."
    )

    @unlisted_post = create(:post,
      metadata: {
        "title" => "Unlisted Post",
        "status" => "unlisted",
        "date" => "2024-01-05"
      },
      content: "# Unlisted Post\n\nThis is an unlisted post."
    )

    @free_member = create(:member, tier: :free, status: :active)
    @paid_member = create(:member, tier: :paid, status: :active)
    @cancelled_member = create(:member, tier: :paid, status: :cancelled)
    @admin = create(:user)
  end

  # ============================================================================
  # Public Content Tests
  # ============================================================================

  test "shows public published post to guest" do
    get post_path(@public_post.url_name)
    assert_response :success
    assert_select "h1", @public_post.metadata["title"]
  end

  test "shows public published post to free member" do
    sign_in_member(@free_member)
    get post_path(@public_post.url_name)
    assert_response :success
  end

  test "shows public published post to paid member" do
    sign_in_member(@paid_member)
    get post_path(@public_post.url_name)
    assert_response :success
  end

  test "shows public published post to admin" do
    sign_in_as(@admin)
    get post_path(@public_post.url_name)
    assert_response :success
  end

  # ============================================================================
  # Unlisted Content Tests
  # ============================================================================

  test "shows unlisted post to guest" do
    get post_path(@unlisted_post.url_name)
    assert_response :success
  end

  test "shows unlisted post to member" do
    sign_in_member(@free_member)
    get post_path(@unlisted_post.url_name)
    assert_response :success
  end

  # ============================================================================
  # Draft Content Tests
  # ============================================================================

  test "returns 404 for draft post when guest" do
    get post_path(@draft_post.url_name)
    assert_response :not_found
  end

  test "returns 404 for draft post when member" do
    sign_in_member(@free_member)
    get post_path(@draft_post.url_name)
    assert_response :not_found
  end

  test "shows draft post to admin" do
    sign_in_as(@admin)
    get post_path(@draft_post.url_name)
    assert_response :success
    assert_select "h1", @draft_post.metadata["title"]
  end

  # ============================================================================
  # Paid Content Tests - No Paywall Form
  # ============================================================================

  test "redirects guest to upgrade when accessing paid content without form" do
    # Enable members feature by creating the feature file
    File.write(File.join(RoeSitePaths::SITE_PATH, "system", "features", "members.yml"), { "enabled" => true }.to_yaml)

    get post_path(@paid_post_no_form.url_name)
    assert_redirected_to "/upgrade"
    assert_equal "This content requires a paid membership", flash[:alert]
  end

  test "redirects free member to upgrade when accessing paid content without form" do
    # Enable members feature by creating the feature file
    File.write(File.join(RoeSitePaths::SITE_PATH, "system", "features", "members.yml"), { "enabled" => true }.to_yaml)

    sign_in_member(@free_member)
    get post_path(@paid_post_no_form.url_name)
    assert_redirected_to "/upgrade"
    assert_equal "This content requires a paid membership", flash[:alert]
  end

  test "shows paid content to paid active member" do
    # Enable members feature by creating the feature file
    File.write(File.join(RoeSitePaths::SITE_PATH, "system", "features", "members.yml"), { "enabled" => true }.to_yaml)

    sign_in_member(@paid_member)
    get post_path(@paid_post_no_form.url_name)
    assert_response :success
    assert_select "h1", @paid_post_no_form.metadata["title"]
  end

  test "redirects cancelled paid member to upgrade" do
    # Enable members feature by creating the feature file
    File.write(File.join(RoeSitePaths::SITE_PATH, "system", "features", "members.yml"), { "enabled" => true }.to_yaml)

    sign_in_member(@cancelled_member)
    get post_path(@paid_post_no_form.url_name)
    assert_redirected_to "/upgrade"
    assert_equal "This content requires a paid membership", flash[:alert]
  end

  test "shows paid content to admin even without membership" do
    SiteConfig.current.update!(
      file_path: "site/system/features/members.yml",
      config: { "enabled" => true }
    )

    sign_in_as(@admin)
    get post_path(@paid_post_no_form.url_name)
    assert_response :success
  end

  # ============================================================================
  # Paid Content Tests - With Paywall Form
  # ============================================================================

  test "shows paid content with paywall form to guest" do
    SiteConfig.current.update!(
      file_path: "site/system/features/members.yml",
      config: { "enabled" => true }
    )

    # With paywall form, content loads but shows teaser
    get post_path(@paid_post_with_form.url_name)
    assert_response :success
  end

  test "shows paid content with paywall form to free member" do
    SiteConfig.current.update!(
      file_path: "site/system/features/members.yml",
      config: { "enabled" => true }
    )

    sign_in_member(@free_member)
    get post_path(@paid_post_with_form.url_name)
    assert_response :success
  end

  test "shows full paid content to paid member even with paywall form" do
    SiteConfig.current.update!(
      file_path: "site/system/features/members.yml",
      config: { "enabled" => true }
    )

    sign_in_member(@paid_member)
    get post_path(@paid_post_with_form.url_name)
    assert_response :success
  end

  # ============================================================================
  # Members Feature Disabled Tests
  # ============================================================================

  test "shows paid content to everyone when members feature is disabled" do
    # Stub members_enabled? to return false (no members.yml file)
    SiteFeature.stubs(:members_enabled?).returns(false)

    get post_path(@paid_post_no_form.url_name)
    assert_response :success
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  test "returns 404 for non-existent post" do
    get post_path("non-existent-post")
    assert_response :not_found
  end

  test "handles post with special characters in url_name" do
    special_post = create(:post,
      metadata: {
        "title" => "Special Post",
        "status" => "published",
        "date" => "2024-01-06",
        "url_name" => "special-post-123"
      }
    )

    get post_path(special_post.url_name)
    assert_response :success
  end

  # ============================================================================
  # Route Tests
  # ============================================================================

  test "show_by_id redirects to named route" do
    get post_by_id_path(@public_post.id)
    assert_redirected_to post_path(@public_post.url_name)
    assert_equal 301, response.status
  end

  test "show_by_id works with different id formats" do
    # Test with string id that looks like a number
    get "/p/#{@public_post.id}"
    assert_redirected_to post_path(@public_post.url_name)
  end
end
