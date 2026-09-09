require "test_helper"

class BulkContentActionsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    @created = []
  end
  teardown { @created.each { |f| File.delete(f) if File.exist?(f) } }

  # `audience` is deliberately set: with memberships configured it's a
  # site-gated field, so a draft without one has publish warnings and bulk
  # publish skips it — correctly. Leaving it out made "clean" depend on
  # whether an earlier test had written a members.yml into the shared test
  # site, which is a test-order coin flip rather than anything about bulk
  # publishing.
  def make_post(name, status:, extra: {})
    meta = { "title" => name, "url_name" => name, "status" => status,
             "post_type" => "article", "date" => "2024-01-01",
             "audience" => "everyone" }.merge(extra)
    slug = ContentWriter.new.write(kind: :post, filename: name, metadata: meta, body: "body")
    @created << File.join(RoeSitePaths::SITE_POSTS_PATH, "#{slug}.md")
    Post.find_by("json_extract(metadata, '$.url_name') = ?", slug)
  end

  test "bulk_destroy deletes selected posts regardless of status" do
    a = make_post("bulk-del-a", status: "draft")
    b = make_post("bulk-del-b", status: "published")

    assert_difference -> { Post.count }, -2 do
      post bulk_destroy_admin_posts_path, params: { ids: [ a.id, b.id ] }
    end
    assert_not File.exist?(File.join(RoeSitePaths::SITE_POSTS_PATH, "bulk-del-a.md"))
    assert_not File.exist?(File.join(RoeSitePaths::SITE_POSTS_PATH, "bulk-del-b.md"))
  end

  test "bulk_publish publishes clean drafts and skips warnings + already-published" do
    clean = make_post("bulk-pub-clean", status: "draft")
    warn  = make_post("bulk-pub-warn", status: "draft", extra: { "image" => "/media/images/nope.jpg" })
    live  = make_post("bulk-pub-live", status: "published")

    assert warn.publish_warnings?, "missing image makes this a warning draft"

    post bulk_publish_admin_posts_path, params: { ids: [ clean.id, warn.id, live.id ] }
    assert_response :redirect

    assert_equal "published", clean.reload.metadata["status"], "clean draft published"
    assert_equal "draft", warn.reload.metadata["status"], "warning draft skipped"
    assert_equal "published", live.reload.metadata["status"], "already-published untouched"
  end

  test "posts index renders the bulk-select UI" do
    make_post("render-check", status: "draft")
    get admin_posts_path
    assert_response :success
    assert_select "[data-controller~=?]", "bulk-select"
    assert_select "button", text: "Select"
    assert_select "form[action=?]", bulk_destroy_admin_posts_path
    assert_select "form[action=?]", bulk_publish_admin_posts_path
  end
end
