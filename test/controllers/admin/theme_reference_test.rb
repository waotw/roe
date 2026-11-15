require "test_helper"

# The theme reference pages: every element a theme styles, from Markdown that
# ships in current/, drawn in the site's own layout. Sample posts and products
# exist only while a page renders.
class Admin::ThemeReferenceTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }

  test "every page renders for an admin, in the site layout, marked noindex" do
    ThemeReference::PAGES.each do |entry|
      get admin_theme_reference_path(entry.slug)
      assert_response :success, entry.slug
      assert_select "#theme-reference-bar a[aria-current=page]", text: entry.title
      assert_select "#theme-reference-bar a[href=?]", admin_themes_path
      assert_select "header.site-nav"
      assert_select "article.page"
      assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    end
  end

  test "the first page opens without naming one" do
    get admin_theme_reference_path
    assert_response :success
    assert_select "#theme-reference-bar a[aria-current=page]", text: "Text"
  end

  # The theme editor's preview has its own page menu, so the bar is left out
  # there; the script that stops sample links and forms still runs.
  test "in the theme editor's preview the bar is left out" do
    get admin_theme_reference_path("forms", in_editor: 1)

    assert_response :success
    assert_select "#theme-reference-bar", 0
    assert_includes response.body, "event.preventDefault(); event.stopImmediatePropagation();"
  end

  test "every page renders in every theme Roe ships, without a block warning" do
    themes = Dir.glob(Rails.root.join("app/themes/*.css")).map { |path| File.basename(path, ".css") }
    Admin::ThemeReferenceController.any_instance.stubs(:installed_themes).returns(themes)
    Page.any_instance.stubs(:show_block_warnings?).returns(true)

    themes.each do |theme|
      ThemeReference::PAGES.each do |entry|
        get admin_theme_reference_path(entry.slug, preview_theme: theme)
        assert_response :success, "#{entry.slug} in #{theme}"
        assert_select "link[rel=stylesheet][href^='/theme/#{theme}.css']"
        assert_no_match(/data-roe-warning|Content not found|Unknown (card|collection|tag)/, response.body,
          "#{entry.slug} in #{theme} shows a block warning")
      end
    end
  end

  test "an unknown page is a 404 and an unknown theme falls back to the active one" do
    get admin_theme_reference_path("nope")
    assert_response :not_found

    get admin_theme_reference_path("text", preview_theme: "../../etc/passwd")
    assert_redirected_to admin_theme_reference_path("text")
  end

  test "a visitor who isn't signed in is sent to sign in, for the pages and the media" do
    delete session_path
    get admin_theme_reference_path("text")
    assert_redirected_to new_session_path

    get admin_theme_reference_media_path("sample-1.jpg")
    assert_redirected_to new_session_path
  end

  test "the sample media is served, with ranges, and nothing outside its folder is" do
    get admin_theme_reference_media_path("sample-audio.mp3")
    assert_response :success
    assert_equal "audio/mpeg", response.media_type

    get admin_theme_reference_media_path("sample-video.mp4"), headers: { "Range" => "bytes=0-99" }
    assert_response :partial_content
    assert_equal 100, response.body.bytesize

    get "/admin/themes/reference/media/..%2F..%2F..%2Fconfig%2Fmaster.key"
    assert_response :not_found
  end

  test "the sample content is gone after the page renders, and nothing is written to site/" do
    skip_dirs = %r{/(db|log|tmp)/}
    site_files = -> {
      Dir.glob(File.join(RoeSitePaths::SITE_PATH, "**", "*")).reject { |path| path.match?(skip_dirs) }.to_h { |path| [ path, File.mtime(path) ] }
    }
    before = site_files.call
    posts, products = Post.count, Product.count

    ThemeReference::PAGES.each { |entry| get admin_theme_reference_path(entry.slug) }

    assert_not SiteFeature.showing_everything?, "features stay as set once the page is drawn"
    assert_equal posts, Post.count
    assert_equal products, Product.count
    assert_nil Post.where("json_extract(metadata, '$.url_name') LIKE ?", "#{ThemeReference::SAMPLE_PREFIX}%").first
    assert_equal before, site_files.call, "the reference pages wrote to site/"
  end

  test "the Themes page links each installed theme to its reference pages" do
    file = Admin::ThemesController::USER_THEME_DIR.join("zz-reference-test.css")
    FileUtils.mkdir_p(file.dirname)
    File.write(file, "body { color: red; }\n")

    get admin_themes_path
    assert_response :success
    assert_select "a[href=?]", admin_theme_reference_path(preview_theme: "zz-reference-test"), text: "Reference"

    get admin_theme_reference_path("text", preview_theme: "zz-reference-test")
    assert_response :success
    assert_select "link[rel=stylesheet][href^='/theme/zz-reference-test.css']"
  ensure
    FileUtils.rm_f(file)
  end

  # New blocks can't be missed: each card type, collection template, gallery
  # option, form and button Roe offers has an example on some page.
  test "every Roe-anji block has an example on a reference page" do
    markdown = ThemeReference::PAGES.map { |entry| ThemeReference.markdown(entry) }.join("\n")

    CardBuilderSchema::TYPES.each do |type|
      assert_match(/^type: #{Regexp.escape(type[:value])}$/, markdown, "no #{type[:value]} card")
    end
    templates = CollectionBuilderSchema::FIELDS.find { |field| field[:key] == "template" }[:options] + [ "grid" ]
    templates.each do |template|
      assert_match(/^template: #{Regexp.escape(template)}$/, markdown, "no #{template} collection")
    end
    GalleryBuilderSchema::DIRECTIVES.each do |directive|
      assert_match(/^#{Regexp.escape(directive)}: /, markdown, "no gallery using #{directive}")
    end
    ActionBuilderSchema::FORM_KINDS.each do |kind|
      assert_match(/^for: #{Regexp.escape(kind[:value])}$/, markdown, "no #{kind[:value]} form")
    end
    ActionBuilderSchema::BUTTON_KINDS.each do |kind|
      next if kind[:value] == "product"

      assert_match(/^for: #{Regexp.escape(kind[:value])}$/, markdown, "no #{kind[:value]} button")
    end
    assert_match(/^sku: /, markdown, "no product button")
    %w[mp3 mp4].each { |ext| assert_match(/!\[[^\]]*\]\([^)]+\.#{ext}\)/, markdown, "no #{ext} embed") }
  end
end
