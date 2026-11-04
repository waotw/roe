require "test_helper"

# A content type's layout draws its page: Roe's default reproduces the old
# post-type templates, a site's own copy changes the order, and a part the
# body already has isn't drawn twice.
class ContentLayoutRenderingTest < ActionDispatch::IntegrationTest
  CARD = "```card\ntype: player\n```".freeze

  teardown do
    Dir.glob(File.join(ContentLayout::SITE_DIR, "*.yml")).each { |f| FileUtils.rm_f(f) }
  end

  def a_post(type = "article", content: "Words.", **fields)
    @n = (@n || 0) + 1
    create(:post,
      metadata: { "title" => "#{type.capitalize} post #{@n}", "status" => "published", "date" => "2024-03-05",
                  "audience" => "everyone", "post_type" => type }.merge(fields.transform_keys(&:to_s)),
      content: content)
  end

  def a_product(content: "About it.", **fields)
    @n = (@n || 0) + 1
    Product.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "products", "thing-#{@n}.md"),
      content: content,
      metadata: { "title" => "Thing #{@n}", "url_name" => "thing-#{@n}", "status" => "published",
                  "sku" => "THING-#{@n}", "price" => 12.0 }.merge(fields.transform_keys(&:to_s)))
  end

  def site_layout(name, text)
    FileUtils.mkdir_p(ContentLayout::SITE_DIR)
    path = ContentLayout.site_path(name)
    File.write(path, text)
    File.utime(Time.now + rand(1..1000), Time.now + rand(1..1000), path)
  end

  # Class names in page order, for the parts we care about.
  def order(*selectors)
    doc = Nokogiri::HTML(response.body)
    doc.css(selectors.join(", ")).map { |n| (n["class"].split & selectors.map { |s| s.delete(".") }).first }
  end

  # ── Roe's defaults ──

  test "an article keeps the old header: title and RSS, subtitle, date and author, then the body" do
    post = a_post(subtitle: "A subtitle", author: "Ben")
    get post_path(post.url_name)

    assert_select "article.post.post-article > .content > header.post-header" do
      assert_select ".post-header-top h1.post-title", post.title
      assert_select ".post-header-top a.feed-link[href='/feed.xml']"
      assert_select "p.post-subtitle", "A subtitle"
      assert_select ".post-meta time.post-date", /March 05, 2024/
      assert_select ".post-meta .post-author", /Ben/
    end
    assert_select "header.post-header + .post-content", /Words/
  end

  test "parts with nothing to show draw nothing" do
    get post_path(a_post.url_name)
    assert_select ".post-subtitle", 0
    assert_select ".post-author", 0
  end

  test "an audio post's player sits between the header and the body" do
    get post_path(a_post("audio", audio: "/media/audio/a.mp3").url_name)
    assert_equal %w[post-header post-player post-content], order(".post-header", ".post-player", ".post-content")
  end

  test "a podcast episode has its player, body and episode list inside .podcast-episode" do
    first = a_post("podcast", audio: "/media/audio/1.mp3", podcast: "show", date: "2024-01-01")
    a_post("podcast", audio: "/media/audio/2.mp3", podcast: "show", date: "2024-02-01")

    get post_path(first.url_name)
    assert_select ".podcast-episode .podcast-hero"
    assert_select ".podcast-episode .post-content"
    assert_select ".podcast-episode .episode-list li", 2
    assert_select ".episode-list li.is-current", 1
  end

  # ── a site's own layout ──

  test "the site's layout changes the order" do
    site_layout("article", "- body\n- title\n")
    post = a_post
    get post_path(post.url_name)
    assert_equal %w[post-content post-title], order(".post-content", ".post-title")
  end

  test "a site's layout without a header part has no post-header" do
    site_layout("article", "- body\n")
    get post_path(a_post.url_name)
    assert_select "header.post-header", 0
    assert_select ".post-title", 0
  end

  test "a group gets one layout-group div" do
    site_layout("article", "- [subtitle, date]\n- body\n")
    get post_path(a_post(subtitle: "Sub").url_name)
    assert_select "div.layout-group.post-meta > .post-subtitle + .post-date"
  end

  test "a metadata field without a part of its own shows its value" do
    site_layout("article", "- location\n- body\n")
    get post_path(a_post(location: "Chicago").url_name)
    assert_select "p.post-field.post-location", "Chicago"
  end

  test "layout: in the metadata picks another layout" do
    site_layout("announcement", "- body\n")
    get post_path(a_post(layout: "announcement").url_name)
    assert_select ".post-title", 0
    assert_select ".post-content", /Words/
  end

  test "Jekyll's layout: page on an imported post keeps the post's header" do
    get post_path(a_post(layout: "page").url_name)
    assert_select "h1.post-title"
  end

  # ── body wins ──

  test "a player card in the body replaces the layout's player" do
    get post_path(a_post("audio", audio: "/media/audio/a.mp3", content: "#{CARD}\n\nWords.").url_name)
    assert_select ".card-player", 1
    assert_select ".post-player", 0
    assert_select ".post-content .card-player"
  end

  test "a page shows only its body by default" do
    page = create(:page, metadata: { "title" => "About", "url_name" => "about-us", "status" => "published" }, content: "# About\n\nHello.")
    get "/#{page.url_name}"
    assert_select "article.page > .content h1", "About"
    assert_select "h1", 1
  end

  test "a product shows its title, image and button from the layout" do
    product = a_product
    get product_path(product.url_name)
    assert_select ".product .content .layout-group.product-top h1.product-title", product.title
    assert_select ".product-top .product-price", "$12.00"
  end

  test "a product whose body has its own heading, image and button shows those only" do
    product = a_product(image: "/media/images/x.jpg",
      content: "![Thing](/media/images/x.jpg)\n\n# My heading\n\n```button\nsku: THING-X\n```\n\nAbout it.")
    get product_path(product.url_name)
    assert_select "h1", 1
    assert_select "h1.product-title", "My heading"
    assert_select ".product-top", 0
  end

  test "an example button inside a four-backtick fence doesn't count" do
    product = a_product(content: "````\n```button\nsku: X\n```\n````\n")
    get product_path(product.url_name)
    assert_select "h1.product-title", product.title
  end
end
