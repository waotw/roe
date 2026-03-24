require "test_helper"

class HasMetadataTest < ActiveSupport::TestCase
  test "published scope returns published posts" do
    published = create(:post, metadata: { "status" => "published", "title" => "Published", "date" => "2024-01-01" })
    draft = create(:post, metadata: { "status" => "draft", "title" => "Draft" })
    
    results = Post.published
    
    assert_includes results, published
    refute_includes results, draft
  end

  test "drafts scope returns draft posts" do
    published = create(:post, metadata: { "status" => "published", "title" => "Published", "date" => "2024-01-01" })
    draft = create(:post, metadata: { "status" => "draft", "title" => "Draft" })
    
    results = Post.drafts
    
    assert_includes results, draft
    refute_includes results, published
  end

  test "unlisted scope returns unlisted posts" do
    published = create(:post, metadata: { "status" => "published", "title" => "Published", "date" => "2024-01-01" })
    unlisted = create(:post, metadata: { "status" => "unlisted", "title" => "Unlisted" })
    
    results = Post.unlisted
    
    assert_includes results, unlisted
    refute_includes results, published
  end

  test "public_items includes published and unlisted" do
    published = create(:post, metadata: { "status" => "published", "title" => "Published", "date" => "2024-01-01" })
    unlisted = create(:post, metadata: { "status" => "unlisted", "title" => "Unlisted" })
    draft = create(:post, metadata: { "status" => "draft", "title" => "Draft" })
    
    results = Post.public_items
    
    assert_includes results, published
    assert_includes results, unlisted
    refute_includes results, draft
  end

  test "tagged_with single tag" do
    ruby_post = create(:post, metadata: { "title" => "Ruby Post", "status" => "published", "tags" => ["ruby", "rails"] })
    python_post = create(:post, metadata: { "title" => "Python Post", "status" => "published", "tags" => ["python"] })
    
    results = Post.tagged_with("ruby")
    
    assert_includes results, ruby_post
    refute_includes results, python_post
  end

  test "tagged_with multiple tags returns posts with any matching tag" do
    ruby_post = create(:post, metadata: { "title" => "Ruby Post", "status" => "published", "tags" => ["ruby"] })
    rails_post = create(:post, metadata: { "title" => "Rails Post", "status" => "published", "tags" => ["rails"] })
    python_post = create(:post, metadata: { "title" => "Python Post", "status" => "published", "tags" => ["python"] })
    
    results = Post.tagged_with(["ruby", "rails"])
    
    assert_includes results, ruby_post
    assert_includes results, rails_post
    refute_includes results, python_post
  end

  test "tagged_with no matching tags returns empty" do
    ruby_post = create(:post, metadata: { "title" => "Ruby Post", "status" => "published", "tags" => ["ruby"] })
    
    results = Post.tagged_with("nonexistent")
    
    assert_empty results
  end

  test "tagged_with handles array format tags" do
    post = create(:post, metadata: { "title" => "Test", "status" => "published", "tags" => ["ruby", "rails"] })
    
    results = Post.tagged_with("ruby")
    
    assert_includes results, post
  end

  test "responds to metadata keys via method missing" do
    post = create(:post, metadata: { "title" => "Test Title", "author" => "Test Author", "status" => "published", "date" => "2024-01-01" })
    
    assert_equal "Test Title", post.title
    assert_equal "Test Author", post.author
  end

  test "does not respond to non_metadata keys" do
    post = create(:post, metadata: { "title" => "Test", "status" => "published", "date" => "2024-01-01" })
    
    assert_raises(NoMethodError) { post.nonexistent_method }
  end

  test "respond_to includes metadata keys" do
    post = create(:post, metadata: { "title" => "Test", "author" => "Author", "status" => "published", "date" => "2024-01-01" })
    
    assert_respond_to post, :title
    assert_respond_to post, :author
    assert_respond_to post, :status
  end

  test "url_name uses explicit slug" do
    post = create(:post, metadata: { "title" => "Test", "url_name" => "custom-slug", "status" => "published", "date" => "2024-01-01" })
    
    assert_equal "custom-slug", post.url_name
  end

  test "url_name falls back to title parameterize" do
    post = create(:post, metadata: { "title" => "Hello World Post", "status" => "published", "date" => "2024-01-01" })
    
    assert_equal "hello-world-post", post.url_name
  end

  test "url_name uses filename when no title" do
    post = create(:post, file_path: "site/posts/my-file-name.md", metadata: { "status" => "published" })
    
    assert_equal "my-file-name", post.url_name
  end

  test "slug is alias for url_name" do
    post = create(:post, metadata: { "title" => "Test", "url_name" => "test-slug", "status" => "published", "date" => "2024-01-01" })
    
    assert_equal post.url_name, post.slug
  end

  test "status defaults to published" do
    post = create(:post, metadata: { "title" => "Test" })
    
    assert_equal "published", post.status
  end

  test "published predicate returns true for published" do
    post = create(:post, metadata: { "status" => "published" })
    
    assert post.published?
    refute post.draft?
    refute post.unlisted?
  end

  test "draft predicate returns true for draft" do
    post = create(:post, metadata: { "status" => "draft" })
    
    assert post.draft?
    refute post.published?
    refute post.unlisted?
  end

  test "unlisted predicate returns true for unlisted" do
    post = create(:post, metadata: { "status" => "unlisted" })
    
    assert post.unlisted?
    refute post.published?
    refute post.draft?
  end

  test "public predicate returns true for published and unlisted" do
    published = create(:post, metadata: { "status" => "published" })
    unlisted = create(:post, metadata: { "status" => "unlisted" })
    draft = create(:post, metadata: { "status" => "draft" })
    
    assert published.public?
    assert unlisted.public?
    refute draft.public?
  end

  test "tags returns array when metadata is array" do
    post = create(:post, metadata: { "tags" => ["ruby", "rails"] })
    
    assert_equal ["ruby", "rails"], post.tags
  end

  test "tags returns array when metadata is string" do
    post = create(:post, metadata: { "tags" => "ruby, rails" })
    
    assert_equal ["ruby", "rails"], post.tags
  end

  test "tags returns empty array for nil" do
    post = create(:post, metadata: {})
    
    assert_equal [], post.tags
  end

  test "with_post_type scope filters by post_type" do
    article = create(:post, metadata: { "post_type" => "article", "title" => "Article", "status" => "published", "date" => "2024-01-01" })
    music = create(:post, metadata: { "post_type" => "music", "title" => "Music", "status" => "published" })
    
    results = Post.with_post_type("article")
    
    assert_includes results, article
    refute_includes results, music
  end

  test "by_date scope orders by date descending" do
    old = create(:post, metadata: { "title" => "Old", "status" => "published", "date" => "2024-01-01" })
    new = create(:post, metadata: { "title" => "New", "status" => "published", "date" => "2024-12-31" })
    
    results = Post.by_date.to_a
    
    assert_equal new.id, results.first.id
    assert_equal old.id, results.last.id
  end
end
