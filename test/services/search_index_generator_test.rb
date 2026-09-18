# frozen_string_literal: true

require "test_helper"

class SearchIndexGeneratorTest < ActiveSupport::TestCase
  def make_post(title:, status: "published", audience: "everyone", body: "Body text.", tags: [])
    Post.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "#{title.parameterize}.md"),
      content: body,
      metadata: { "title" => title, "status" => status, "audience" => audience, "tags" => tags }
    )
  end

  def make_page(title, url_name:, status: "published", audience: "everyone")
    Page.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "pages", "#{url_name}.md"),
      content: "Page body.",
      metadata: { "title" => title, "url_name" => url_name, "status" => status, "audience" => audience }
    )
  end

  def grouped_product(title, variant:, primary: false, group: "book")
    Product.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "products", "#{title.parameterize}.md"),
      content: "A great book.",
      metadata: {
        "title" => title, "status" => "published", "price" => 10,
        "group" => group, "variant" => variant, "primary" => primary
      }
    )
  end

  def write_nav(content)
    dir = RoeSitePaths::SITE_LAYOUT_PATH
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "navigation.md"), content)
  end

  def teardown
    nav = File.join(RoeSitePaths::SITE_LAYOUT_PATH, "navigation.md")
    File.delete(nav) if File.exist?(nav)
  end

  def entries
    SearchIndexGenerator.build[:entries]
  end

  def page_titles
    entries.select { |e| e[:type] == "pages" }.map { |e| e[:title] }
  end

  def entry_titled(title)
    entries.find { |e| e[:title] == title }
  end

  # --- page inclusion rules -----------------------------------------------

  test "by default indexes only pages linked in nav/footer" do
    make_page("About", url_name: "about")
    make_page("Secret Landing", url_name: "secret-landing")
    write_nav("[Blog](/blog) [About](/about)")

    assert_includes page_titles, "About"
    refute_includes page_titles, "Secret Landing"
  end

  test "search_all_pages indexes every published public page" do
    SiteConfig.stubs(:get).returns(nil)
    SiteConfig.stubs(:get).with("search_all_pages").returns("true")
    make_page("About", url_name: "about")
    make_page("Secret Landing", url_name: "secret-landing")
    write_nav("")

    assert_includes page_titles, "About"
    assert_includes page_titles, "Secret Landing"
  end

  test "unlisted page is excluded even when linked in nav" do
    make_page("Hidden", url_name: "hidden", status: "unlisted")
    write_nav("[Hidden](/hidden)")

    refute_includes page_titles, "Hidden"
  end

  # --- bundled Roe documentation -----------------------------------------

  def make_doc(title, folder:, status: "published")
    Documentation.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "documentation", folder, "#{title.parameterize}.md"),
      content: "Doc body.",
      metadata: { "title" => title, "status" => status }
    )
  end

  def doc_titles
    entries.select { |e| e[:type] == "documentation" }.map { |e| e[:title] }
  end

  test "documentation/roe is excluded from search by default" do
    make_doc("Getting Started", folder: "roe")
    make_doc("My Guide", folder: "guides")

    assert_includes doc_titles, "My Guide"
    refute_includes doc_titles, "Getting Started"
  end

  test "search_roe_docs includes bundled Roe documentation" do
    SiteConfig.stubs(:get).returns(nil)
    SiteConfig.stubs(:get).with("search_roe_docs").returns("true")
    make_doc("Getting Started", folder: "roe")

    assert_includes doc_titles, "Getting Started"
  end

  test "a user folder starting with roe is not mistaken for the bundled folder" do
    make_doc("Roadmap", folder: "roering")

    assert_includes doc_titles, "Roadmap"
  end

  test "indexes a published public post with body text" do
    make_post(title: "Hello World", body: "The quick brown fox.")

    e = entry_titled("Hello World")
    assert e, "expected published post indexed"
    assert_equal "posts", e[:type]
    assert_includes e[:text], "quick brown fox"
    assert_equal false, e[:paid]
  end

  test "excludes drafts" do
    make_post(title: "Secret Draft", status: "draft")
    assert_nil entry_titled("Secret Draft")
  end

  test "excludes unlisted" do
    make_post(title: "Hidden", status: "unlisted")
    assert_nil entry_titled("Hidden")
  end

  test "paid post excluded when show_paid_content is off" do
    SiteConfig.stubs(:feature).returns(nil)
    make_post(title: "Paid Piece", audience: "paid", body: "secret paid body")

    assert_nil entry_titled("Paid Piece")
  end

  test "paid post indexed as teaser (no body) when show_paid_content is on" do
    SiteConfig.stubs(:feature).returns(nil)
    SiteConfig.stubs(:feature).with("members", "everyone.show_paid_content").returns("true")
    make_post(title: "Paid Teaser", audience: "paid", body: "secret paid body")

    e = entry_titled("Paid Teaser")
    assert e, "expected paid teaser indexed"
    assert_equal true, e[:paid]
    refute_includes e[:text].to_s, "secret paid body"
  end

  # --- paywall split ---------------------------------------------------------

  PAYWALLED = "Free intro everyone may read.\n\n```form for: paid_content\nUpgrade now!\n```\n\nSecret paid body below the wall."
  PAYWALLED_MULTILINE = "Free intro everyone may read.\n\n```form\nfor: paid_content\nbutton: Upgrade\n```\n\nSecret paid body below the wall."

  test "public index carries a paid post's text above the paywall but nothing below" do
    SiteConfig.stubs(:feature).returns(nil)
    SiteConfig.stubs(:feature).with("members", "everyone.show_paid_content").returns("true")
    make_post(title: "Walled", audience: "paid", body: PAYWALLED)

    e = entry_titled("Walled")
    assert_includes e[:text], "Free intro everyone may read"
    refute_includes e[:text], "Secret paid body"
    refute_includes e[:text], "Upgrade now"
  end

  test "paywall with for: paid_content on its own line splits the same way" do
    SiteConfig.stubs(:feature).returns(nil)
    SiteConfig.stubs(:feature).with("members", "everyone.show_paid_content").returns("true")
    make_post(title: "Walled Two", audience: "paid", body: PAYWALLED_MULTILINE)

    e = entry_titled("Walled Two")
    assert_includes e[:text], "Free intro everyone may read"
    refute_includes e[:text], "Secret paid body"
  end

  test "a paid post with no paywall is fully gated, so only its excerpt is public" do
    SiteConfig.stubs(:feature).returns(nil)
    SiteConfig.stubs(:feature).with("members", "everyone.show_paid_content").returns("true")
    make_post(title: "No Wall", audience: "paid", body: "Every word here is paid.")

    refute_includes entry_titled("No Wall")[:text], "Every word here is paid"
  end

  # --- paid audience (members' index) ---------------------------------------

  def paid_entries
    SearchIndexGenerator.build(audience: :paid)[:entries]
  end

  test "paid index carries a paid post's full text, including below the paywall" do
    SiteConfig.stubs(:feature).returns(nil)
    make_post(title: "Walled", audience: "paid", body: PAYWALLED)

    e = paid_entries.find { |x| x[:title] == "Walled" }
    assert e, "paid post should be in the paid index"
    assert_includes e[:text], "Secret paid body below the wall"
    assert_equal true, e[:paid]
  end

  test "paid index includes paid posts even when show_paid_content is off" do
    SiteConfig.stubs(:feature).returns(nil)
    make_post(title: "Hidden Teaser", audience: "paid", body: "secret paid body")

    assert_nil entry_titled("Hidden Teaser"), "public index excludes it"
    assert paid_entries.find { |x| x[:title] == "Hidden Teaser" }, "paid index includes it"
  end

  test "paid index still excludes drafts and only_paid" do
    SiteConfig.stubs(:feature).returns(nil)
    make_post(title: "Draft Paid", audience: "paid", status: "draft")
    make_post(title: "Only Paid", audience: "only_paid")

    titles = paid_entries.map { |x| x[:title] }
    refute_includes titles, "Draft Paid"
    refute_includes titles, "Only Paid"
  end

  test "rejects an unknown audience" do
    assert_raises(ArgumentError) { SearchIndexGenerator.build(audience: :admin) }
  end

  test "indexes products (which lack HasAudience) as public" do
    Product.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "products", "widget.md"),
      content: "A great widget.",
      metadata: { "title" => "Widget", "status" => "published", "price" => 10, "sku" => "W-1" }
    )

    e = entry_titled("Widget")
    assert e, "product should be indexed"
    assert_equal "products", e[:type]
    assert_equal false, e[:paid]
  end

  test "indexes only the primary of a grouped product (variants collapse)" do
    grouped_product("Book Paperback", variant: "Paperback", primary: true)
    grouped_product("Book Hardback", variant: "Hardback")

    product_titles = entries.select { |e| e[:type] == "products" }.map { |e| e[:title] }
    assert_equal [ "Book Paperback" ], product_titles,
                 "grouped variants should collapse to just the primary"
  end

  test "carries tags and post_type for scoping" do
    make_post(title: "Tagged", tags: %w[ruby rails])

    e = entry_titled("Tagged")
    assert_equal %w[ruby rails], e[:tags]
    assert e.key?(:post_type)
  end
end
