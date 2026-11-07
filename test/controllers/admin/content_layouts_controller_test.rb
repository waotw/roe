require "test_helper"

# The Content section of the Layouts page: every type editable straight away,
# saved as the site's copy, back to Roe's default, and new layouts.
class Admin::ContentLayoutsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    FileUtils.mkdir_p(ContentLayout::SITE_DIR)
  end

  teardown do
    Dir.glob(File.join(ContentLayout::SITE_DIR, "*#{ContentLayout::EXT}")).each { |f| FileUtils.rm_f(f) }
    restore_sidebar
  end

  # The editor frames the textarea with the site's header, sidebar and footer.
  def write_sidebar(frontmatter)
    @sidebar_original = File.exist?(Sidebar.path) ? File.binread(Sidebar.path) : false if @sidebar_original.nil?
    FileUtils.mkdir_p(File.dirname(Sidebar.path))
    File.write(Sidebar.path, "---\n#{frontmatter}---\n\nSidebar\n")
  end

  def remove_sidebar
    @sidebar_original = File.exist?(Sidebar.path) ? File.binread(Sidebar.path) : false if @sidebar_original.nil?
    FileUtils.rm_f(Sidebar.path)
  end

  def restore_sidebar
    return if @sidebar_original.nil?

    @sidebar_original ? File.binwrite(Sidebar.path, @sidebar_original) : FileUtils.rm_f(Sidebar.path)
  end

  def frame_order
    css_select("[data-layout-frame], textarea[name=content]").map { |el| el["data-layout-frame"] || "content" }
  end

  test "the editor frames the layout with the header and footer" do
    remove_sidebar
    get "/admin/layouts/content/article/edit"
    assert_equal %w[header content footer], frame_order
  end

  test "a left sidebar sits before the layout, a right one after" do
    write_sidebar("position: left\n")
    get "/admin/layouts/content/article/edit"
    assert_equal %w[header sidebar content footer], frame_order
    assert_select "a[data-layout-frame=sidebar][href=?]", "/admin/layout/sidebar/edit"

    write_sidebar("position: right\n")
    get "/admin/layouts/content/article/edit"
    assert_equal %w[header content sidebar footer], frame_order
  end

  test "the sidebar is left out for a type its scope doesn't cover" do
    write_sidebar("scope: pages\n")
    get "/admin/layouts/content/article/edit"
    assert_select "[data-layout-frame=sidebar]", 0

    get "/admin/layouts/content/page/edit"
    assert_select "[data-layout-frame=sidebar]", 1
  end

  test "the Layouts page lists the site files and every content type" do
    SiteFeature.stubs(:podcast_enabled?).returns(true)
    SiteFeature.stubs(:music_enabled?).returns(true)
    SiteFeature.stubs(:store_enabled?).returns(true)

    get "/admin/layouts"
    assert_response :success
    assert_select "h2", "Site"
    assert_select "h2", "Content"
    %w[article podcast music page podcast-page music-page product documentation].each do |name|
      assert_select "a[href=?]", "/admin/layouts/content/#{name}/edit"
    end
    assert_select "th", "Status"
    assert_select "td span", "default"
  end

  test "layouts are grouped like products: posts by type, then pages, products, documentation" do
    SiteFeature.stubs(:podcast_enabled?).returns(true)
    SiteFeature.stubs(:store_enabled?).returns(true)

    get "/admin/layouts"
    groups = css_select("tbody[data-layout-group]").map { |t| t["data-layout-group"] }
    assert_equal %w[posts pages products documentation], groups
    assert_select "tbody[data-layout-group=posts] td", text: "Article"
    assert_select "tbody[data-layout-group=pages] td", text: "Podcast page"
  end

  test "podcast, music and store layouts are hidden while their feature is off" do
    SiteFeature.stubs(:podcast_enabled?).returns(false)
    SiteFeature.stubs(:music_enabled?).returns(false)
    SiteFeature.stubs(:store_enabled?).returns(false)

    get "/admin/layouts"
    %w[podcast music podcast-page music-page product].each do |name|
      assert_select "a[href=?]", "/admin/layouts/content/#{name}/edit", count: 0
    end
    assert_select "tbody[data-layout-group=products]", 0
    assert_select "a[href=?]", "/admin/layouts/content/article/edit"
  end

  test "a customised layout stays listed even with its feature off" do
    SiteFeature.stubs(:podcast_enabled?).returns(false)
    File.write(ContentLayout.site_path("podcast"), "[body]\n")

    get "/admin/layouts"
    assert_select "a[href=?]", "/admin/layouts/content/podcast/edit"
  end

  test "a type on Roe's default opens Roe's copy, and saving makes it the site's" do
    get "/admin/layouts/content/article/edit"
    assert_response :success
    assert_includes response.body, File.read(ContentLayout.roe_default_path("article")).lines.last.strip
    assert_not File.exist?(ContentLayout.site_path("article")), "opening it writes nothing"

    patch "/admin/layouts/content/article", params: { content: "[body]\r\n[title]\r\n" }
    assert_redirected_to "/admin/layouts/content/article/edit"
    assert_equal "[body]\n[title]\n", File.read(ContentLayout.site_path("article"))
  end

  test "saving a layout with a problem saves it and says what's wrong" do
    patch "/admin/layouts/content/article", params: { content: "[title]\n" }
    assert File.exist?(ContentLayout.site_path("article"))
    assert_match(/no \[body\]/, flash[:alert])
  end

  test "Use default deletes the custom file" do
    File.write(ContentLayout.site_path("article"), "[body]\n")
    delete "/admin/layouts/content/article"
    assert_not File.exist?(ContentLayout.site_path("article"))
    assert_redirected_to "/admin/layouts/content/article/edit"
  end

  test "New layout creates a file to use with layout:" do
    post "/admin/layouts/content", params: { name: "announcement" }
    assert_redirected_to "/admin/layouts/content/announcement/edit"
    assert File.exist?(ContentLayout.site_path("announcement"))

    get "/admin/layouts"
    assert_includes response.body, "layout: announcement"
  end

  test "New layout refuses a type's name and anything that isn't a plain name" do
    post "/admin/layouts/content", params: { name: "article" }
    assert_match(/already a layout/, flash[:alert])

    post "/admin/layouts/content", params: { name: "../evil" }
    assert_match(/lowercase/, flash[:alert])
    assert_empty Dir.glob(File.join(ContentLayout::SITE_DIR, "*#{ContentLayout::EXT}"))
  end

  test "explain describes unsaved text without writing anything" do
    post "/admin/layouts/content/article/explain", params: { content: "[title]\n\n[body]\n" }, as: :json
    assert_response :success
    json = response.parsed_body
    assert_includes json["html"].map { |e| e["text"] }, "<header>"
    assert_match(/title/, json["lines"]["1"]["boxes"].first["text"])
    assert_not File.exist?(ContentLayout.site_path("article"))
  end

  test "the editor carries the help for the layout it opens" do
    get "/admin/layouts/content/article/edit"
    assert_select "[data-controller=layout-explain][data-layout-explain-initial-value*=post-header]"
  end

  test "a name that isn't a layout's can't be read or written" do
    get "/admin/layouts/content/nope/edit"
    assert_redirected_to "/admin/layouts"

    patch "/admin/layouts/content/..%2Fheader", params: { content: "x" }
    assert_response :not_found
  end
end
