require "test_helper"

# Products live at /products/<name>, as posts live at /posts/<name>. The store
# is an ordinary page marked `page_type: store`, at any address, and a page
# with `category: <category>` is that category's page. Before 0.5.1 products
# were at /store/<name>; those addresses keep working.
class StorePagesTest < ActionDispatch::IntegrationTest
  setup do
    @files = []
    SiteFeature.stubs(:store_enabled?).returns(true)
    SiteFeature.stubs(:snipcart_enabled?).returns(false)
    Current.home_page_lookup = nil
  end

  teardown do
    @files.each { |file| FileUtils.rm_f(file) }
    Product.where(file_path: @files.map { |f| f.delete_prefix("#{RoeSitePaths::SITE_PATH}/") }).destroy_all
    Page.where(file_path: @files.map { |f| RoeSitePaths.normalize(f) }).destroy_all
  end

  def write(rel, yaml, body = "Body.")
    path = File.join(RoeSitePaths::SITE_PATH, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "---\n#{yaml}---\n#{body}\n")
    @files << path
    ContentSync.sync_file(path)
    path
  end

  def product(name, category: "Fiction", status: "published")
    write("products/sp-#{name}.md", "title: #{name.titleize}\nurl_name: #{name}\ncategory: #{category}\nprice: 10\nstatus: #{status}\n")
    Product.find_by!(file_path: "products/sp-#{name}.md")
  end

  def page(name, extra = "", status: "published", body: "Body.")
    path = write("pages/sp-#{name}.md", "title: #{name.titleize}\nurl_name: #{name}\nstatus: #{status}\n#{extra}", body)
    Page.find_by!(file_path: RoeSitePaths.normalize(path))
  end

  def crumbs
    css_select("nav.breadcrumbs a").map { |a| [ a.text, a["href"] ] }
  end

  # ── Product addresses ─────────────────────────────────────────────────────

  test "a product lives at /products/<name>" do
    item = product("my-book")
    assert_equal "/products/my-book", item.public_url

    get "/products/my-book"
    assert_response :success
    assert_select "link[rel=canonical][href$=?]", "/products/my-book"
  end

  test "the old /store/<name> address still serves the product, pointing search engines at the new one" do
    product("my-book")

    get "/store/my-book"
    assert_response :success
    assert_select "link[rel=canonical][href$=?]", "/products/my-book"
  end

  test "an old /store/ address with no product goes to /products/, and an old category crumb to the category" do
    product("my-book", category: "Science Fiction")

    get "/store/renamed-book"
    assert_redirected_to "/products/renamed-book"
    assert_response :moved_permanently

    get "/store/science-fiction"
    assert_redirected_to "/products/category/science-fiction"
  end

  # ── The store page ────────────────────────────────────────────────────────

  test "the breadcrumbs link to the page marked page_type: store, wherever it lives" do
    page("bookshop", "page_type: store\n")
    product("my-book")

    get "/products/my-book"
    assert_includes crumbs, [ "Bookshop", "/bookshop" ]
  end

  test "without page_type, a page called store is still the store page" do
    page("store")
    product("my-book")

    get "/products/my-book"
    assert_includes crumbs, [ "Store", "/store" ]
  end

  test "without a store page, Store is plain text" do
    product("my-book")

    get "/products/my-book"
    assert_select "nav.breadcrumbs span.breadcrumb-text", "Store"
    assert_not crumbs.any? { |text, _| text == "Store" }
  end

  test "a draft store page isn't linked" do
    page("bookshop", "page_type: store\n", status: "draft")
    product("my-book")

    get "/products/my-book"
    assert_not crumbs.any? { |_, href| href == "/bookshop" }
  end

  # ── Categories ────────────────────────────────────────────────────────────

  test "a category crumb goes to Roe's listing, which lists the category's products whatever their case" do
    product("my-book", category: "Fiction")
    product("other-book", category: "fiction")
    product("a-poster", category: "posters")

    get "/products/my-book"
    assert_includes crumbs, [ "Fiction", "/products/category/fiction" ]

    get "/products/category/fiction"
    assert_response :success
    assert_select "h1", "Fiction"
    assert_select "a[href^=?]", "/products/my-book"
    assert_select "a[href^=?]", "/products/other-book"
    assert_select "a[href^=?]", "/products/a-poster", count: 0
  end

  test "a category no published product is in has no listing" do
    product("draft-book", category: "drafts", status: "draft")

    get "/products/category/drafts"
    assert_response :not_found
    get "/products/category/nothing"
    assert_response :not_found
  end

  test "a page with category: is the category's page, at its own address" do
    product("my-book", category: "Fiction")
    page("novels", "category: fiction\n")

    get "/products/my-book"
    assert_includes crumbs, [ "Novels", "/novels" ]

    get "/products/category/fiction"
    assert_redirected_to "/novels"
    assert_response :moved_permanently
  end

  test "a draft category page doesn't count, and the store page is never a category's" do
    product("my-book", category: "fiction")
    page("novels", "category: fiction\n", status: "draft")
    page("bookshop", "page_type: store\ncategory: fiction\n")

    get "/products/my-book"
    assert_includes crumbs, [ "Fiction", "/products/category/fiction" ]
  end

  test "when two pages claim a category, the older one wins" do
    product("my-book", category: "fiction")
    first = page("novels", "category: fiction\n")
    second = page("stories", "category: Fiction\n")
    second.update_column(:created_at, first.created_at + 1.minute)

    assert_equal first, StorePages.category_page("fiction")
  end

  test "the page editor offers category: with the store on, keeping a value as the file writes it" do
    field = ContentMetadataSchema.fields_for("pages", metadata: { "category" => "Fiction" })["category"]
    assert_includes field[:options], "Fiction"
    assert_not_includes field[:options], "fiction", "one entry, as written, so the select shows it"
  end

  # ── The links check ───────────────────────────────────────────────────────

  def link_problems
    LinkCheck.new.call["problems"].select { |p| p["field"] == "category" }
  end

  test "the links check reports a category no product is in, a second claim, and the store page's category" do
    product("my-book", category: "fiction")
    page("typo", "category: fictoin\n")
    first = page("novels", "category: fiction\n")
    second = page("stories", "category: fiction\n")
    second.update_column(:created_at, first.created_at + 1.minute)
    page("bookshop", "page_type: store\ncategory: fiction\n")

    problems = link_problems.to_h { |p| [ p["title"], p ] }
    assert_equal "broken_internal_link", problems.dig("Typo", "type")
    assert_equal "unclear_name", problems.dig("Stories", "type")
    assert_equal "unclear_name", problems.dig("Bookshop", "type")
    assert_not problems.key?("Novels")
  end

  test "a link to a category's address is checked" do
    product("my-book", category: "fiction")

    assert_equal :ok, LinkTargets.address_status("/products/category/fiction").first
    assert_equal :missing, LinkTargets.address_status("/products/category/nope").first
    assert_equal :ok, LinkTargets.address_status("/products/my-book").first
    assert_equal :ok, LinkTargets.address_status("/store/my-book").first
  end

  # ── The static build ──────────────────────────────────────────────────────

  test "the static build writes products and category listings under /products, and drops old store/ copies" do
    dir = Rails.root.join("tmp", "store-pages-static-test")
    FileUtils.rm_rf(dir)
    FileUtils.mkdir_p(dir.join("store"))
    File.write(dir.join("store", "my-book.html"), "old")
    item = product("my-book", category: "fiction")

    generator = StaticGenerator.new(output_dir: dir)
    generator.send(:remove_legacy_store_files)
    generator.send(:generate_product, item)
    generator.send(:generate_product_categories)

    assert dir.join("products", "my-book.html").exist?
    assert dir.join("products", "category", "fiction.html").exist?
    assert_not dir.join("store").exist?, "a store/ folder next to store.html can hide the store page on a static host"
  ensure
    FileUtils.rm_rf(dir) if dir
  end
end
