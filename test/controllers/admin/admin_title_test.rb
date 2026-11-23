require "test_helper"

# Admin tabs say which site and which page: "Roe - <site> - <page>".
class AdminTitleTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }

  def site = SiteConfig.get("title").presence

  test "an admin page is named by its heading" do
    get admin_links_path
    assert_select "title", [ "Roe", site, "Links" ].compact.join(" - ")
  end

  test "a heading's badges are left out" do
    get admin_orders_path
    assert_select "title", [ "Roe", site, "Summary of Orders" ].compact.join(" - ")
  end

  test "a page that sets its own title keeps it" do
    get admin_tags_path
    assert_select "title", [ "Roe", site, "Tags" ].compact.join(" - ")
  end

  test "the editor names the item being edited" do
    slug = ContentWriter.new.write(kind: :post, filename: "at-titled",
                                   metadata: { "title" => "At Titled", "status" => "draft", "date" => "2024-01-01", "post_type" => "article" },
                                   body: "x")
    path = File.join(RoeSitePaths::SITE_POSTS_PATH, "#{slug}.md")
    ContentSync.sync_file(path)

    get edit_admin_post_path(Post.find_by(file_path: RoeSitePaths.normalize(path)))
    assert_select "head title", [ "Roe", site, "Edit Post: At Titled" ].compact.join(" - ")
  ensure
    File.delete(path) if path && File.exist?(path)
  end
end
