require "test_helper"

# Content layouts are off unless content.yml turns them on. Off, every page
# uses Roe's defaults whatever the site has saved, the editor isn't
# reachable, and the Layouts page just says how to turn them on. The site's
# files are left alone, so turning them back on restores them.
class ContentLayoutsOffTest < ActionDispatch::IntegrationTest
  setup do
    SiteConfig.stubs(:content_layouts?).returns(false)
    FileUtils.mkdir_p(ContentLayout::SITE_DIR)
    File.write(ContentLayout.site_path("article"), "[body]\n[title]\n")
    File.write(ContentLayout.site_path("announcement"), "[body]\n")
  end

  teardown do
    Dir.glob(File.join(ContentLayout::SITE_DIR, "*#{ContentLayout::EXT}")).each { |f| FileUtils.rm_f(f) }
  end

  def a_post(**fields)
    create(:post, metadata: { "title" => "Hello", "status" => "published", "date" => "2024-03-05",
                              "audience" => "everyone", "post_type" => "article" }.merge(fields.transform_keys(&:to_s)),
                  content: "Words.")
  end

  test "is off unless content.yml says true" do
    SiteConfig.unstub(:content_layouts?)
    SiteConfig.stubs(:content).with("content_layouts").returns(nil)
    assert_not SiteConfig.content_layouts?
    SiteConfig.stubs(:content).with("content_layouts").returns(true)
    assert SiteConfig.content_layouts?
  end

  test "pages use Roe's default and ignore the site's file and layout:" do
    assert_equal :roe, ContentLayout.for(a_post).source
    assert_equal "article", ContentLayout.for(a_post(layout: "announcement")).name

    get post_path(a_post(url_name: "hello-off").url_name)
    doc = Nokogiri::HTML(response.body)
    title = doc.at_css("h1.post-title")
    body = doc.at_css(".post-content")
    assert title && body
    assert title.line < body.line, "Roe's default puts the title above the writing"
  end

  test "the site's files are kept, and used again once it's back on" do
    assert File.file?(ContentLayout.site_path("article"))
    SiteConfig.stubs(:content_layouts?).returns(true)
    assert_equal :site, ContentLayout.for(a_post).source
  end

  test "the editor goes back to the Layouts page" do
    sign_in_as(users(:one))
    get admin_edit_content_layout_path("article")
    assert_redirected_to admin_layouts_path

    post admin_content_layouts_path, params: { name: "another" }
    assert_redirected_to admin_layouts_path
    assert_not File.file?(ContentLayout.site_path("another"))
  end

  test "the Layouts page shows only the heading and how to turn them on" do
    sign_in_as(users(:one))
    get admin_layouts_path
    assert_response :success
    assert_select "a[href=?]", admin_edit_content_config_path(focus: "content_layouts")
    assert_select "a[href=?]", admin_edit_content_layout_path("article"), 0
    assert_select "input[name=name][placeholder=announcement]", 0
  end

  test "the setting is on the Content settings page" do
    sign_in_as(users(:one))
    get admin_edit_content_config_path
    assert_select "[data-config-field=content_layouts]"
  end
end
