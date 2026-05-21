require "test_helper"

class CollectionMembersFilterTest < ActiveSupport::TestCase
  def setup
    super
    
    @public_post = create(:post,
      metadata: {
        "title" => "Public Post",
        "status" => "published",
        "date" => "2024-01-01",
        "audience" => "everyone"
      }
    )

    @paid_post = create(:post,
      metadata: {
        "title" => "Paid Post",
        "status" => "published",
        "date" => "2024-01-02",
        "audience" => "paid"
      }
    )

    @no_audience_post = create(:post,
      metadata: {
        "title" => "No Audience Post",
        "status" => "published",
        "date" => "2024-01-03"
        # audience is nil
      }
    )
  end

  # ============================================================================
  # Members Feature Disabled
  # ============================================================================

  test "returns all posts when members feature is disabled" do
    SiteConfig.stubs(:feature_enabled?).with('members').returns(false)

    items = Post.published
    result = CollectionMembersFilter.filter(items)

    assert_includes result, @public_post
    assert_includes result, @paid_post
    assert_includes result, @no_audience_post
  end

  # ============================================================================
  # Members Feature Enabled - Show Paid Content
  # ============================================================================

  test "shows all posts when show_paid is true" do
    SiteConfig.stubs(:feature_enabled?).with('members').returns(true)
    SiteConfig.stubs(:feature).with('members', 'everyone.show_paid_content').returns(true)

    items = Post.published
    result = CollectionMembersFilter.filter(items)

    assert_includes result, @public_post
    assert_includes result, @paid_post
    assert_includes result, @no_audience_post
  end

  test "shows all posts when show_paid config is overridden to true" do
    SiteConfig.stubs(:feature_enabled?).with('members').returns(true)
    SiteConfig.stubs(:feature).with('members', 'everyone.show_paid_content').returns(false)

    items = Post.published
    result = CollectionMembersFilter.filter(items, show_paid: 'true')

    assert_includes result, @public_post
    assert_includes result, @paid_post
    assert_includes result, @no_audience_post
  end

  # ============================================================================
  # Members Feature Enabled - Hide Paid Content
  # ============================================================================

  test "hides paid posts when show_paid is false" do
    SiteConfig.stubs(:feature_enabled?).with('members').returns(true)
    SiteConfig.stubs(:feature).with('members', 'everyone.show_paid_content').returns(false)

    items = Post.published
    result = CollectionMembersFilter.filter(items)

    assert_includes result, @public_post
    assert_not_includes result, @paid_post
    assert_includes result, @no_audience_post
  end

  test "hides paid posts when show_paid config is not set" do
    SiteConfig.stubs(:feature_enabled?).with('members').returns(true)
    SiteConfig.stubs(:feature).with('members', 'everyone.show_paid_content').returns(nil)

    items = Post.published
    result = CollectionMembersFilter.filter(items)

    assert_includes result, @public_post
    assert_not_includes result, @paid_post
    assert_includes result, @no_audience_post
  end

  test "shows paid posts to paid members regardless of settings" do
    SiteConfig.stubs(:feature_enabled?).with('members').returns(true)
    SiteConfig.stubs(:feature).with('members', 'everyone.show_paid_content').returns(false)

    paid_member = create(:member, tier: :paid, status: :active)

    items = Post.published
    result = CollectionMembersFilter.filter(items, current_member: paid_member)

    # Paid member should see all posts including paid
    assert_includes result, @public_post
    assert_includes result, @paid_post
    assert_includes result, @no_audience_post
  end

  test "hides paid posts from free members" do
    SiteConfig.stubs(:feature_enabled?).with('members').returns(true)
    SiteConfig.stubs(:feature).with('members', 'everyone.show_paid_content').returns(false)

    free_member = create(:member, tier: :free, status: :active)

    items = Post.published
    result = CollectionMembersFilter.filter(items, current_member: free_member)

    # Free member should not see paid posts
    assert_includes result, @public_post
    assert_not_includes result, @paid_post
    assert_includes result, @no_audience_post
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  test "handles empty collection" do
    SiteConfig.stubs(:feature_enabled?).with('members').returns(true)
    SiteConfig.stubs(:feature).with('members', 'everyone.show_paid_content').returns(false)

    empty_posts = Post.where(id: [])
    result = CollectionMembersFilter.filter(empty_posts)

    assert_empty result
  end

  test "handles array input (returns as-is)" do
    SiteConfig.stubs(:feature_enabled?).with('members').returns(true)
    SiteConfig.stubs(:feature).with('members', 'everyone.show_paid_content').returns(false)

    posts_array = [ @public_post, @paid_post ]
    result = CollectionMembersFilter.filter(posts_array)

    # When input is an array, it returns as-is without filtering
    assert_includes result, @public_post
    assert_includes result, @paid_post
  end

  test "handles posts with nil audience" do
    SiteConfig.stubs(:feature_enabled?).with('members').returns(true)
    SiteConfig.stubs(:feature).with('members', 'everyone.show_paid_content').returns(false)

    items = Post.published
    result = CollectionMembersFilter.filter(items)

    # Posts with nil audience should be shown
    assert_includes result, @no_audience_post
  end

  test "class method works the same as instance method" do
    SiteConfig.stubs(:feature_enabled?).with('members').returns(true)
    SiteConfig.stubs(:feature).with('members', 'everyone.show_paid_content').returns(false)

    items = Post.published

    # Test class method
    class_result = CollectionMembersFilter.filter(items)

    # Test instance method
    instance_result = CollectionMembersFilter.new(items).filter

    assert_equal class_result.to_a, instance_result.to_a
  end

  test "filter preserves relation chainability" do
    SiteConfig.stubs(:feature_enabled?).with('members').returns(true)
    SiteConfig.stubs(:feature).with('members', 'everyone.show_paid_content').returns(false)

    items = Post.published
    result = CollectionMembersFilter.filter(items)

    # Should be able to chain additional ActiveRecord methods
    assert_respond_to result, :order
    assert_respond_to result, :limit
  end

  test "does not modify original relation" do
    SiteConfig.stubs(:feature_enabled?).with('members').returns(true)
    SiteConfig.stubs(:feature).with('members', 'everyone.show_paid_content').returns(false)

    original_count = Post.published.count

    items = Post.published
    CollectionMembersFilter.filter(items)

    # Original relation should not be modified
    assert_equal original_count, Post.published.count
  end
end
