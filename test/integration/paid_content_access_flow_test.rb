require "test_helper"

class PaidContentAccessFlowTest < ActionDispatch::IntegrationTest
  def setup
    super
    
    @free_member = create(:member,
      name: "Free Member",
      email: "free@example.com",
      tier: :free,
      status: :active
    )
    
    @paid_member = create(:member,
      name: "Paid Member",
      email: "paid@example.com",
      tier: :paid,
      status: :active
    )
    
    @cancelled_member = create(:member,
      name: "Cancelled Member",
      email: "cancelled@example.com",
      tier: :paid,
      status: :cancelled
    )
    
    @public_post = create(:post,
      metadata: {
        "title" => "Public Post",
        "status" => "published",
        "date" => "2024-01-01",
        "audience" => "everyone"
      },
      content: "# Public Post\n\nThis is free content."
    )
    
    @paid_post = create(:post,
      metadata: {
        "title" => "Premium Post",
        "status" => "published",
        "date" => "2024-01-02",
        "audience" => "paid"
      },
      content: "# Premium Post\n\nThis is exclusive paid content."
    )
    
    @paid_post_with_teaser = create(:post,
      metadata: {
        "title" => "Premium with Teaser",
        "status" => "published",
        "date" => "2024-01-03",
        "audience" => "paid"
      },
      content: "# Teaser Content\n\nThis is the free preview.\n\n```form for: paid_content\nUpgrade to read more!\n```\n\n# Premium Section\n\nThis is the paid-only content."
    )
    
    # Enable members feature
    SiteFeature.stubs(:members_enabled?).returns(true)
    
    # Create required pages
    create(:page,
      metadata: {
        "title" => "Upgrade",
        "status" => "published",
        "url_name" => "upgrade"
      },
      content: "# Upgrade\n\nPlease upgrade to access premium content."
    )
  end

  # ============================================================================
  # Public Content Access (Everyone)
  # ============================================================================

  test "guest can access public content" do
    get post_path(@public_post.url_name)
    
    assert_response :success
    assert_includes response.body, "Public Post"
    assert_includes response.body, "This is free content"
  end

  test "free member can access public content" do
    sign_in_member(@free_member)
    get post_path(@public_post.url_name)
    
    assert_response :success
    assert_includes response.body, "Public Post"
  end

  test "paid member can access public content" do
    sign_in_member(@paid_member)
    get post_path(@public_post.url_name)
    
    assert_response :success
    assert_includes response.body, "Public Post"
  end

  # ============================================================================
  # Paid Content Access - No Paywall Form
  # ============================================================================

  test "guest is redirected to upgrade for paid content without form" do
    get post_path(@paid_post.url_name)
    
    assert_redirected_to "/upgrade"
    assert_equal "This content requires a paid membership", flash[:alert]
  end

  test "free member is redirected to upgrade for paid content without form" do
    sign_in_member(@free_member)
    get post_path(@paid_post.url_name)
    
    assert_redirected_to "/upgrade"
    assert_equal "This content requires a paid membership", flash[:alert]
  end

  test "cancelled member is redirected to upgrade for paid content" do
    sign_in_member(@cancelled_member)
    get post_path(@paid_post.url_name)
    
    assert_redirected_to "/upgrade"
    assert_equal "This content requires a paid membership", flash[:alert]
  end

  test "active paid member can access paid content without form" do
    sign_in_member(@paid_member)
    get post_path(@paid_post.url_name)
    
    assert_response :success
    assert_includes response.body, "Premium Post"
    assert_includes response.body, "This is exclusive paid content"
  end

  # ============================================================================
  # Paid Content Access - With Paywall Form (Teaser)
  # ============================================================================

  test "guest sees teaser for paid content with paywall form" do
    get post_path(@paid_post_with_teaser.url_name)
    
    # Page loads but shows only teaser
    assert_response :success
    assert_includes response.body, "Teaser Content"
    assert_includes response.body, "This is the free preview"
  end

  test "free member sees teaser for paid content with paywall form" do
    sign_in_member(@free_member)
    get post_path(@paid_post_with_teaser.url_name)
    
    assert_response :success
    assert_includes response.body, "Teaser Content"
    assert_includes response.body, "This is the free preview"
  end

  test "paid member sees full content with paywall form" do
    sign_in_member(@paid_member)
    get post_path(@paid_post_with_teaser.url_name)
    
    assert_response :success
    assert_includes response.body, "Teaser Content"
    assert_includes response.body, "Premium Section"
    assert_includes response.body, "This is the paid-only content"
  end

  # ============================================================================
  # Collection Filtering
  # ============================================================================

  test "collection excludes paid posts for guests when members enabled" do
    get "/posts"
    
    assert_response :success
    assert_includes response.body, "Public Post"
    # Should not show paid post in collection
    refute_includes response.body, "Premium Post"
  end

  test "collection shows paid posts to paid members" do
    sign_in_member(@paid_member)
    get "/posts"
    
    assert_response :success
    assert_includes response.body, "Public Post"
    assert_includes response.body, "Premium Post"
  end

  # ============================================================================
  # Direct URL Access Attempts
  # ============================================================================

  test "guest cannot bypass paywall via direct URL" do
    # Try to access paid post directly
    get "/posts/#{@paid_post.url_name}"
    
    assert_redirected_to "/upgrade"
    
    # Even with format parameter
    get "/posts/#{@paid_post.url_name}?format=html"
    assert_redirected_to "/upgrade"
  end

  test "member cannot access draft posts" do
    draft_post = create(:post,
      metadata: {
        "title" => "Draft Post",
        "status" => "draft",
        "date" => "2024-01-04"
      },
      content: "# Draft\n\nNot published yet."
    )
    
    sign_in_member(@paid_member)
    get post_path(draft_post.url_name)
    
    assert_response :not_found
  end

  # ============================================================================
  # Admin Override
  # ============================================================================

  test "admin can access all content without membership" do
    admin = create(:user)
    sign_in_as(admin)
    
    # Can access paid content
    get post_path(@paid_post.url_name)
    assert_response :success
    assert_includes response.body, "Premium Post"
    
    # Can access draft content
    draft_post = create(:post,
      metadata: {
        "title" => "Draft Post",
        "status" => "draft",
        "date" => "2024-01-04"
      },
      content: "# Draft"
    )
    get post_path(draft_post.url_name)
    assert_response :success
  end
end
