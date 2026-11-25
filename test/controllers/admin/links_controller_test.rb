require "test_helper"

# The Links page, CHECK NOW, and the dashboard's LINKS box.
class Admin::LinksControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    @created = []
    File.delete(LinkCheck::STORE) if File.exist?(LinkCheck::STORE)
  end

  teardown do
    @created.each { |f| File.delete(f) if File.exist?(f) }
    File.delete(LinkCheck::STORE) if File.exist?(LinkCheck::STORE)
  end

  def make_post(name, body:, meta: {})
    metadata = { "title" => name.titleize, "status" => "published", "date" => "2024-01-01", "post_type" => "article" }.merge(meta)
    slug = ContentWriter.new.write(kind: :post, filename: name, metadata: metadata, body: body)
    path = File.join(RoeSitePaths::SITE_POSTS_PATH, "#{slug}.md")
    @created << path
    ContentSync.sync_file(path)
    Post.find_by(file_path: RoeSitePaths.normalize(path))
  end

  test "before the first check the page and the box say so" do
    get admin_links_path
    assert_response :success
    assert_select "[data-test=links-checked]", /Not checked yet/

    get admin_root_path
    assert_select "[data-test=dashboard-links-checked]", /Not checked yet/
  end

  test "each problem's item links to its editor, landing on the line or the field" do
    post_record = make_post("lcc-source", body: "Intro.\n[[posts/lcc-gone]]\n", meta: { "image" => "/media/images/lcc-gone.jpg" })
    LinkCheck.run!

    get admin_links_path

    assert_response :success
    assert_select "[data-test=links-section-links] a[data-test=links-item][href*=?]",
                  "#{edit_admin_post_path(post_record)}?highlight=posts%2Flcc-gone&line=2&link=1"
    assert_select "[data-test=links-section-media] a[data-test=links-item][href*=?]",
                  "#{edit_admin_post_path(post_record)}?field=image&highlight=%2Fmedia%2Fimages%2Flcc-gone.jpg"
    assert_select "[data-test=links-section-drafts] [data-test=links-empty]"
  end

  test "CHECK NOW runs the check and goes back where it was pressed" do
    make_post("lcc-now", body: "[[posts/lcc-also-gone]]\n")

    post admin_check_links_path, headers: { "HTTP_REFERER" => admin_root_url }

    assert_redirected_to admin_root_url
    assert LinkCheck.latest
    follow_redirect!
    assert_select "[data-test=dashboard-links-broken] td", /\d/
    assert_select "[data-test=dashboard-links-checked]", /Checked \d\d:\d\d/
  end

  test "the editor gets the line, field and link flag from the Links page" do
    post_record = make_post("lcc-edit", body: "x\n")

    get edit_admin_post_path(post_record, highlight: "posts/x", line: 2, link: 1)

    assert_select "[data-editor-highlight-line-value='2'][data-editor-highlight-link-value='true']"
  end
end
