require "test_helper"

class Admin::PostsDuplicateTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    @dir = File.join(RoeSitePaths::SITE_PATH, "posts")
    FileUtils.mkdir_p(@dir)
    File.write(File.join(@dir, "my-post.md"), "---\ntitle: My Post\nstatus: draft\ntags: []\n---\nBody here\n")
    ContentSync.sync_file(File.join(@dir, "my-post.md"))
    @post = Post.where("json_extract(metadata, '$.title') = ?", "My Post").first
  end

  teardown do
    Dir.glob(File.join(@dir, "my-post*.md")).each { |f| File.delete(f) }
  end

  test "duplicate creates a numbered copy on disk and redirects to its editor" do
    assert @post, "source post synced from file"

    assert_difference -> { Post.count }, 1 do
      post duplicate_admin_post_path(@post)
    end

    assert File.exist?(File.join(@dir, "my-post-2.md")), "wrote my-post-2.md"
    dup = Post.order(:id).last
    assert_equal "My Post 2", dup.title
    assert_redirected_to edit_admin_post_path(dup)
  end

  test "duplicate increments past copies that already exist" do
    File.write(File.join(@dir, "my-post-2.md"), "---\ntitle: My Post 2\n---\nx\n")

    post duplicate_admin_post_path(@post)

    assert File.exist?(File.join(@dir, "my-post-3.md")), "skipped -2, wrote -3"
  end

  test "editor renders the filename rename control and the duplicate button" do
    get edit_admin_post_path(@post)

    assert_response :success
    assert_select "form[action=?]", duplicate_admin_post_path(@post)
    assert_includes response.body, "my-post.md"
    assert_includes response.body, "Double-click to rename"
  end

  test "index rows render icon actions (edit/view/duplicate/delete) and one delete modal" do
    get admin_posts_path

    assert_response :success
    assert_includes response.body, "<svg", "icons rendered"
    assert_includes response.body, duplicate_admin_post_path(@post), "duplicate action present"
    assert_includes response.body, %(data-action="delete"), "delete trigger present"
    assert_includes response.body, %(data-delete-url="#{admin_post_path(@post)}"), "delete retargets the modal per row"
    assert_includes response.body, %(id="delete-modal-post"), "shared delete modal present"
  end

  test "rename returns to the editor when return_to is the editor path" do
    patch rename_admin_post_path(@post),
          params: { new_filename: "my-post-renamed", return_to: edit_admin_post_path(@post) }

    assert_redirected_to edit_admin_post_path(@post)
    assert File.exist?(File.join(@dir, "my-post-renamed.md"))
    refute File.exist?(File.join(@dir, "my-post.md"))
  end

  test "rename falls back to the index without return_to" do
    patch rename_admin_post_path(@post), params: { new_filename: "my-post-renamed" }

    assert_redirected_to admin_posts_path
  end

  test "rename ignores an off-site return_to (no open redirect)" do
    patch rename_admin_post_path(@post),
          params: { new_filename: "my-post-renamed", return_to: "//evil.com/x" }

    assert_redirected_to admin_posts_path
  end
end
