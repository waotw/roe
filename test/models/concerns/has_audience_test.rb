require "test_helper"

class HasAudienceTest < ActiveSupport::TestCase
  # Create test models that include the concern
  setup do
    @post_class = Post
    @page_class = Page
    
    @free_member = create(:member, tier: :free, status: :active)
    @paid_member = create(:member, tier: :paid, status: :active)
    @cancelled_member = create(:member, tier: :paid, status: :cancelled)
  end

  # Instance method: audience
  test "audience returns 'everyone' when metadata is nil" do
    post = create(:post, metadata: { "title" => "Test" })
    assert_equal "everyone", post.audience
  end

  test "audience returns 'everyone' when metadata is empty string" do
    post = create(:post, metadata: { "audience" => "" })
    assert_equal "everyone", post.audience
  end

  test "audience returns 'everyone' when metadata is whitespace" do
    post = create(:post, metadata: { "audience" => "   " })
    assert_equal "everyone", post.audience
  end

  test "audience returns stored value when set" do
    post = create(:post, metadata: { "audience" => "paid" })
    assert_equal "paid", post.audience
  end

  test "audience returns 'only_paid' when set" do
    post = create(:post, metadata: { "audience" => "only_paid" })
    assert_equal "only_paid", post.audience
  end

  # Instance method: audience=
  test "audience= writes to metadata" do
    post = create(:post, metadata: {})
    post.audience = "paid"
    assert_equal "paid", post.metadata["audience"]
  end

  # Instance method: publicly_accessible?
  test "publicly_accessible? returns true for everyone audience" do
    post = create(:post, metadata: { "audience" => "everyone" })
    assert post.publicly_accessible?
  end

  test "publicly_accessible? returns true for nil audience" do
    post = create(:post, metadata: {})
    assert post.publicly_accessible?
  end

  test "publicly_accessible? returns false for paid audience" do
    post = create(:post, metadata: { "audience" => "paid" })
    assert_not post.publicly_accessible?
  end

  # Instance method: premium?
  test "premium? returns true for paid audience" do
    post = create(:post, metadata: { "audience" => "paid" })
    assert post.premium?
  end

  test "premium? returns false for everyone audience" do
    post = create(:post, metadata: { "audience" => "everyone" })
    assert_not post.premium?
  end

  test "premium? returns false for only_paid audience" do
    post = create(:post, metadata: { "audience" => "only_paid" })
    assert_not post.premium?
  end

  # Instance method: accessible_to?
  test "accessible_to? returns true for public content regardless of member" do
    post = create(:post, metadata: { "audience" => "everyone" })
    
    assert post.accessible_to?(nil)
    assert post.accessible_to?(@free_member)
    assert post.accessible_to?(@paid_member)
    assert post.accessible_to?(@cancelled_member)
  end

  test "accessible_to? returns false for premium content when member is nil" do
    post = create(:post, metadata: { "audience" => "paid" })
    assert_not post.accessible_to?(nil)
  end

  test "accessible_to? returns false for premium content when member is free" do
    post = create(:post, metadata: { "audience" => "paid" })
    assert_not post.accessible_to?(@free_member)
  end

  test "accessible_to? returns true for premium content when member is paid and active" do
    post = create(:post, metadata: { "audience" => "paid" })
    assert post.accessible_to?(@paid_member)
  end

  test "accessible_to? returns false for premium content when member is paid but cancelled" do
    post = create(:post, metadata: { "audience" => "paid" })
    assert_not post.accessible_to?(@cancelled_member)
  end

  # Instance method: newsletter_audience
  test "newsletter_audience returns 'paid' for premium content" do
    post = create(:post, metadata: { "audience" => "paid" })
    assert_equal "paid", post.newsletter_audience
  end

  test "newsletter_audience returns 'everyone' for public content" do
    post = create(:post, metadata: { "audience" => "everyone" })
    assert_equal "everyone", post.newsletter_audience
  end

  test "newsletter_audience returns 'everyone' for only_paid content" do
    post = create(:post, metadata: { "audience" => "only_paid" })
    assert_equal "everyone", post.newsletter_audience
  end

  # Scope: public_content
  test "public_content scope includes posts with nil audience" do
    public_post = create(:post, metadata: { "title" => "Public" })
    paid_post = create(:post, metadata: { "audience" => "paid" })
    
    results = Post.public_content
    assert_includes results, public_post
    assert_not_includes results, paid_post
  end

  test "public_content scope includes posts with empty audience" do
    public_post = create(:post, metadata: { "audience" => "" })
    
    assert_includes Post.public_content, public_post
  end

  test "public_content scope includes posts with everyone audience" do
    public_post = create(:post, metadata: { "audience" => "everyone" })
    
    assert_includes Post.public_content, public_post
  end

  test "public_content scope excludes posts with paid audience" do
    paid_post = create(:post, metadata: { "audience" => "paid" })
    
    assert_not_includes Post.public_content, paid_post
  end

  # Scope: premium_content
  test "premium_content scope includes posts with paid audience" do
    paid_post = create(:post, metadata: { "audience" => "paid" })
    
    assert_includes Post.premium_content, paid_post
  end

  test "premium_content scope excludes posts with everyone audience" do
    public_post = create(:post, metadata: { "audience" => "everyone" })
    
    assert_not_includes Post.premium_content, public_post
  end

  # Scope: accessible_to
  test "accessible_to scope returns all content for paid active member" do
    public_post = create(:post, metadata: { "audience" => "everyone" })
    paid_post = create(:post, metadata: { "audience" => "paid" })
    
    results = Post.accessible_to(@paid_member)
    assert_includes results, public_post
    assert_includes results, paid_post
  end

  test "accessible_to scope returns only public content for free member" do
    public_post = create(:post, metadata: { "audience" => "everyone" })
    paid_post = create(:post, metadata: { "audience" => "paid" })
    
    results = Post.accessible_to(@free_member)
    assert_includes results, public_post
    assert_not_includes results, paid_post
  end

  test "accessible_to scope returns only public content for nil member" do
    public_post = create(:post, metadata: { "audience" => "everyone" })
    paid_post = create(:post, metadata: { "audience" => "paid" })
    
    results = Post.accessible_to(nil)
    assert_includes results, public_post
    assert_not_includes results, paid_post
  end

  test "accessible_to scope returns only public content for cancelled paid member" do
    public_post = create(:post, metadata: { "audience" => "everyone" })
    paid_post = create(:post, metadata: { "audience" => "paid" })
    
    results = Post.accessible_to(@cancelled_member)
    assert_includes results, public_post
    assert_not_includes results, paid_post
  end

  # Works with different content types
  test "HasAudience works with Page model" do
    public_page = create(:page, metadata: { "audience" => "everyone" })
    paid_page = create(:page, metadata: { "audience" => "paid" })
    
    assert public_page.publicly_accessible?
    assert paid_page.premium?
    assert Page.public_content.include?(public_page)
    assert_not Page.public_content.include?(paid_page)
  end

  test "HasAudience works with Documentation model" do
    doc = create(:documentation, metadata: { "audience" => "paid" })
    
    assert doc.premium?
    assert_not doc.publicly_accessible?
    assert_not doc.accessible_to?(@free_member)
    assert doc.accessible_to?(@paid_member)
  end
end
