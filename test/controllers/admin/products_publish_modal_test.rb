# frozen_string_literal: true

require "test_helper"

# The product publish modal reflects the metadata editor: present required
# fields show as read-only "✓" confirmation bullets, missing ones as inputs.
# Category is dropped while SKU is missing (it's picked in the SKU generator).
class Admin::ProductsPublishModalTest < ActionDispatch::IntegrationTest
  # SKU and price are only required for the cart, so these are a store with
  # Snipcart on. The test site has no store.yml, which counts as Snipcart off.
  setup do
    sign_in_as(User.take)
    SiteFeature.stubs(:snipcart_enabled?).returns(true)
  end

  def teardown
    File.delete(File.join(RoeSitePaths::SITE_PATH, "products", "pm-test.md")) rescue nil
    File.delete(File.join(RoeSitePaths::SITE_PATH, "products", "pm-cat.md")) rescue nil
  end

  test "category input gets autocomplete when categories exist (SKU present)" do
    ProductCategory.stubs(:all).returns(%w[book poster])
    rel = "products/pm-cat.md"
    path = File.join(RoeSitePaths::SITE_PATH, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "---\ntitle: \"Widget\"\nprice: 10\nsku: BOOK-001\nstatus: draft\nurl_name: pm-cat\n---\nBody.\n")
    record = Product.create!(
      file_path: rel,
      content: "Body.",
      metadata: { "title" => "Widget", "price" => 10, "sku" => "BOOK-001", "status" => "draft", "url_name" => "pm-cat" }
    )

    post publish_modal_admin_product_path(record),
         params: { metadata: "title: Widget\nprice: 10\nsku: BOOK-001\nstatus: draft\nurl_name: pm-cat\n" }

    assert_response :success
    # SKU present, so category shows as its own input — with autocomplete.
    assert_includes response.body, 'name="metadata_fields[category]"'
    assert_includes response.body, 'data-controller="autocomplete"'
    assert_includes response.body, "book"
  end

  test "present fields are ✓ bullets, missing are inputs, category hidden while SKU missing" do
    rel = "products/pm-test.md"
    path = File.join(RoeSitePaths::SITE_PATH, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "---\ntitle: \"Widget\"\nprice: 10\nstatus: draft\nurl_name: pm-test\n---\nBody.\n")
    record = Product.create!(
      file_path: rel,
      content: "Body.",
      metadata: { "title" => "Widget", "price" => 10, "status" => "draft", "url_name" => "pm-test" }
    )

    # Mirror how the editor posts the current metadata editor state.
    post publish_modal_admin_product_path(record),
         params: { metadata: "title: Widget\nprice: 10\nstatus: draft\nurl_name: pm-test\n" }

    assert_response :success
    # Present → confirmation bullets.
    assert_includes response.body, "✓"
    assert_includes response.body, "Title"
    # Missing → inputs.
    assert_includes response.body, 'name="metadata_fields[sku]"'
    assert_includes response.body, 'name="metadata_fields[image]"'
    assert_includes response.body, "Generate SKU"
    # Category is subsumed by the SKU while SKU is missing.
    assert_not_includes response.body, 'name="metadata_fields[category]"'
    # The URL name field shows a product's real address, not a post's.
    assert_includes response.body, "/store/pm-test"
    assert_includes response.body, "this product's web address"
  end

  # Pages render the same modal. It once read @post directly, which is nil for
  # a page or product, so publishing either one crashed before the modal opened.
  test "a page's publish modal opens, with the page's address" do
    rel = "pages/pm-page.md"
    path = File.join(RoeSitePaths::SITE_PATH, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "---\ntitle: \"About Us\"\nstatus: draft\n---\nBody.\n")
    record = Page.create!(file_path: rel, content: "Body.", metadata: { "title" => "About Us", "status" => "draft" })

    post publish_modal_admin_page_path(record), params: { metadata: "title: About Us\nstatus: draft\n" }

    assert_response :success
    assert_includes response.body, "/about-us"
    assert_not_includes response.body, "/posts/about-us"
    assert_includes response.body, "this page's web address"
  ensure
    File.delete(path) rescue nil
  end
end
