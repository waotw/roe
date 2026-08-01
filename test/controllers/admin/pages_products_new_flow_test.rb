# frozen_string_literal: true

require "test_helper"

# Pages and products share the New Post form (shared/_new_content_form), minus
# the type picker. They had the same blank-filename hole that wrote a dotfile,
# and a new product needs a SKU or its buy button can't work.
class Admin::PagesProductsNewFlowTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    @created = []
    %w[pages products].each { |d| FileUtils.mkdir_p(File.join(RoeSitePaths::SITE_PATH, d)) }
  end
  teardown { @created.each { |f| File.delete(f) if File.exist?(f) } }

  def track(dir, filename)
    path = File.join(RoeSitePaths::SITE_PATH, dir, "#{filename}.md")
    @created << path
    path
  end

  # --- pages ---------------------------------------------------------------

  test "the new page form asks for a title and a filename, and no post_type" do
    get new_admin_page_path

    assert_response :success
    assert_includes response.body, 'data-controller="new-content"'
    assert_includes response.body, 'data-new-content-target="title"'
    assert_includes response.body, 'data-new-content-target="filename"'
    assert_not_includes response.body, 'data-new-content-target="postType"',
      "pages have no sub-types"
  end

  test "a page's filename is derived from its title" do
    path = track("pages", "about-us")

    post admin_pages_path, params: { filename: "", title: "About Us" }

    assert File.exist?(path), "the filename should follow from the title"
    assert_not File.exist?(File.join(RoeSitePaths::SITE_PATH, "pages", ".md")),
      "a dotfile must never be written"
    assert_includes File.read(path), 'title: "About Us"'
  end

  test "a page with neither title nor filename is refused" do
    post admin_pages_path, params: { filename: "", title: "" }

    assert_response :unprocessable_entity
    assert_not File.exist?(File.join(RoeSitePaths::SITE_PATH, "pages", ".md"))
  end

  test "a page takes an audience when members is on" do
    SiteFeature.stubs(:members_enabled?).returns(true)
    path = track("pages", "members-only")

    post admin_pages_path, params: { title: "Members Only", fields: { audience: "paid" } }

    assert_includes File.read(path), 'audience: "paid"'
  end

  # --- products ------------------------------------------------------------

  test "the new product form asks for the fields a product can't work without" do
    get new_admin_product_path

    assert_response :success
    %w[category price sku image].each do |name|
      assert_includes response.body, %(name="fields[#{name}]"), "#{name} should be asked for"
    end
    assert_includes response.body, 'data-media-type="images"', "image gets the picker"
  end

  # Products sit outside the members system.
  test "a product is never asked for an audience" do
    SiteFeature.stubs(:members_enabled?).returns(true)

    get new_admin_product_path
    assert_not_includes response.body, 'name="fields[audience]"'
  end

  test "an audience submitted for a product is ignored" do
    SiteFeature.stubs(:members_enabled?).returns(true)
    path = track("products", "sneaky")

    post admin_products_path, params: { title: "Sneaky", fields: { audience: "paid" } }

    assert_not_includes File.read(path), "audience"
  end

  test "a product arrives with its fields, a body that renders, and a SKU" do
    path = track("products", "the-zine")

    post admin_products_path, params: {
      title: "The Zine",
      fields: { category: "zine", price: "12.00", image: "/media/images/zine.jpg" }
    }

    content = File.read(path)
    assert_includes content, "The Zine"
    assert_includes content, "zine"
    assert_includes content, "12.00"
    # Snipcart keys on the SKU; without one the buy button can't work.
    assert_match(/sku: ["']?ZINE-/, content, "a SKU is suggested when none is given")
    # Scaffolded body: image, title, buy button.
    assert_includes content, "![The Zine](/media/images/zine.jpg)"
    assert_includes content, "# The Zine"
    assert_includes content, "```button"
  end

  test "the sku field offers a generator and a collision warning" do
    get new_admin_product_path

    assert_response :success
    assert_includes response.body, 'data-action="click->new-content#generateSku"'
    assert_includes response.body, 'data-new-content-target="sku"'
    assert_includes response.body, "data-unique-warning"
  end

  # The button and the create-time fallback must agree, or the SKU you're shown
  # isn't the SKU you get.
  test "suggest_sku returns what create would have generated" do
    get suggest_sku_admin_products_path, params: { title: "The Zine", category: "zine" }

    assert_response :success
    suggested = JSON.parse(response.body)["sku"]
    assert_match(/\AZINE-\d{3}-THEZINE\z/, suggested)

    path = track("products", "the-zine-2")
    post admin_products_path, params: { filename: "the-zine-2",
                                        title: "The Zine", fields: { category: "zine" } }
    assert_includes File.read(path), suggested
  end

  test "a supplied SKU is kept" do
    path = track("products", "own-sku")

    post admin_products_path, params: {
      title: "Own Sku", fields: { category: "zine", price: "1.00", sku: "MY-SKU-1" }
    }

    assert_includes File.read(path), "MY-SKU-1"
  end

  test "a product's filename is derived from its title" do
    path = track("products", "derived-product")

    post admin_products_path, params: { filename: "", title: "Derived Product" }

    assert File.exist?(path)
    assert_not File.exist?(File.join(RoeSitePaths::SITE_PATH, "products", ".md"))
  end

  test "fields a resource doesn't declare are ignored" do
    path = track("pages", "no-injection")

    post admin_pages_path, params: { title: "No Injection", fields: { status: "published", price: "9" } }

    content = File.read(path)
    assert_includes content, 'status: "draft"', "status isn't a create field and can't be forced"
    assert_not_includes content, "price"
  end
end
