require "test_helper"

class ContentSyncTest < ActiveSupport::TestCase
  def setup
    @temp_dir = Dir.mktmpdir("content_sync_test")
    @original_root = Rails.root

    @posts_dir = File.join(@temp_dir, "posts")
    @pages_dir = File.join(@temp_dir, "pages")
    @docs_dir = File.join(@temp_dir, "documentation")

    FileUtils.mkdir_p([ @posts_dir, @pages_dir, @docs_dir ])

    ContentSync.any_instance.stubs(:sync_all) # Skip full sync in setup
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
    super
  end

  def write_test_file(relative_path, content)
    full_path = File.join(@temp_dir, relative_path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
    full_path
  end

  test "creates new post from file" do
    content = <<~YAML
      ---
      title: Test Post
      date: 2024-01-15
      tags:
        - test
      ---

      # Test Post

      This is test content.
    YAML

    file_path = write_test_file("posts/test-post.md", content)

    result = Post.create_or_update_from_file(file_path)

    assert result.persisted?
    assert_equal "Test Post", result.title
    assert_equal "published", result.status
  end

  test "updates existing post from file" do
    content = <<~YAML
      ---
      title: Original Title
      date: 2024-01-15
      status: published
      ---

      # Original Title
    YAML

    file_path = write_test_file("posts/test-post.md", content)
    post = Post.create_or_update_from_file(file_path)
    original_id = post.id

    updated_content = content.gsub("Original Title", "Updated Title")
    File.write(file_path, updated_content)

    updated_post = Post.create_or_update_from_file(file_path)

    assert_equal original_id, updated_post.id
    assert_equal "Updated Title", updated_post.title
  end

  test "orphan detection removes deleted files" do
    content = <<~YAML
      ---
      title: Orphan Post
      date: 2024-01-15
      status: published
      ---

      # Orphan Post
    YAML

    file_path = write_test_file("posts/orphan-post.md", content)
    post = Post.create_or_update_from_file(file_path)
    orphan_id = post.id

    File.delete(file_path)

    ContentSync.new.send(:handle_orphaned_posts, [])

    assert_nil Post.find_by(id: orphan_id)
  end

  test "rename detection matches similar basenames" do
    content = <<~YAML
      ---
      title: Article Title
      date: 2024-01-15
      status: published
      ---

      # Article Title
    YAML

    old_path = write_test_file("posts/article.md", content)
    post = Post.create_or_update_from_file(old_path)
    original_id = post.id

    new_content = content.gsub("Article Title", "Updated Article Title")
    new_path = write_test_file("posts/updated-article.md", new_content)

    ContentSync.new.send(:handle_orphaned_posts, [ new_path ])

    post.reload
    assert_equal new_path, post.file_path
    assert_equal original_id, post.id
  end

  test "rename detection handles number prefix" do
    content = <<~YAML
      ---
      title: Post
      date: 2024-01-15
      status: published
      ---

      # Post
    YAML

    old_path = write_test_file("posts/post.md", content)
    post = Post.create_or_update_from_file(old_path)
    original_id = post.id

    new_content = content.gsub("# Post", "# Renamed Post")
    new_path = write_test_file("posts/2024-01-15-post.md", new_content)

    ContentSync.new.send(:handle_orphaned_posts, [ new_path ])

    post.reload
    assert_equal new_path, post.file_path
    assert_equal original_id, post.id
  end

  test "invalid date returns nil" do
    content = <<~YAML
      ---
      title: Bad Date Post
      date: not-a-date
      status: published
      ---

      # Bad Date Post
    YAML

    file_path = write_test_file("posts/bad-date.md", content)

    result = Post.create_or_update_from_file(file_path)

    assert_nil result
  end

  test "missing title on published post warns" do
    content = <<~YAML
      ---
      date: 2024-01-15
      status: published
      ---

      # No Title
    YAML

    file_path = write_test_file("posts/no-title.md", content)

    result = Post.create_or_update_from_file(file_path)

    assert result.is_a?(Symbol) && result == :warning
  end

  test "missing date on published post warns" do
    content = <<~YAML
      ---
      title: No Date Post
      status: published
      ---

      # No Date Post
    YAML

    file_path = write_test_file("posts/no-date.md", content)

    result = Post.create_or_update_from_file(file_path)

    assert result.is_a?(Symbol) && result == :warning
  end

  test "duplicate cleanup removes extra records" do
    content = <<~YAML
      ---
      title: Duplicate Test
      date: 2024-01-15
      status: published
      ---

      # Duplicate Test
    YAML

    file_path = write_test_file("posts/duplicate.md", content)

    Post.create_or_update_from_file(file_path)
    Post.create_or_update_from_file(file_path)
    Post.create_or_update_from_file(file_path)

    assert_equal 1, Post.where(file_path: RoeSitePaths.normalize(file_path)).count
  end

  test "string tags converted to array" do
    content = <<~YAML
      ---
      title: Tags Test
      date: 2024-01-15
      status: published
      tags: ruby, rails, tutorial
      ---

      # Tags Test
    YAML

    file_path = write_test_file("posts/tags-test.md", content)
    post = Post.create_or_update_from_file(file_path)

    assert_equal [ "ruby", "rails", "tutorial" ], post.tags
  end

  test "pages sync works" do
    content = <<~YAML
      ---
      title: Test Page
      ---

      # Test Page
    YAML

    file_path = write_test_file("pages/test-page.md", content)
    result = Page.create_or_update_from_file(file_path)

    assert result.persisted?
    assert_equal "Test Page", result.title
  end

  test "documentation sync works" do
    content = <<~YAML
      ---
      title: Test Doc
      ---

      # Test Documentation
    YAML

    file_path = write_test_file("documentation/test-doc.md", content)
    result = Documentation.create_or_update_from_file(file_path)

    assert result.persisted?
    assert_equal "Test Doc", result.title
  end

  test "sync_file routes to correct model for posts" do
    content = <<~YAML
      ---
      title: Route Test
      date: 2024-01-15
      status: published
      ---

      # Route Test
    YAML

    file_path = write_test_file("posts/route-test.md", content)
    result = ContentSync.sync_file(file_path)

    assert_equal :success, result
    assert Post.exists?(file_path: RoeSitePaths.normalize(file_path))
  end

  test "sync_file routes to correct model for pages" do
    content = <<~YAML
      ---
      title: Page Route Test
      ---

      # Page Route Test
    YAML

    file_path = write_test_file("pages/page-route-test.md", content)
    result = ContentSync.sync_file(file_path)

    assert_equal :success, result
    assert Page.exists?(file_path: RoeSitePaths.normalize(file_path))
  end

  test "removes post by file path" do
    content = <<~YAML
      ---
      title: Remove Test
      date: 2024-01-15
      status: published
      ---

      # Remove Test
    YAML

    file_path = write_test_file("posts/remove-test.md", content)
    Post.create_or_update_from_file(file_path)

    assert_difference "Post.count", -1 do
      Post.remove_by_file_path(file_path)
    end
  end

  test "handles parse errors gracefully" do
    content = <<~YAML
      ---
      invalid yaml: [
      ---

      # Content
    YAML

    file_path = write_test_file("posts/broken.md", content)
    result = ContentSync.sync_file(file_path)

    assert_equal :error, result
  end
end
