# frozen_string_literal: true

require "test_helper"

# A single product's price is carried as data-item-price for Snipcart but never
# rendered, so `show_price: true` is what puts it on the page. Variant lists
# print their own prices and must not double up.
class ProductButtonRendererTest < ActiveSupport::TestCase
  setup do
    @created = []
    FileUtils.mkdir_p(RoeSitePaths::SITE_PRODUCTS_PATH)
  end
  teardown { @created.each { |f| File.delete(f) if File.exist?(f) } }

  def write_product(name, extra = {})
    meta = { "title" => name.tr("-", " "), "url_name" => name, "status" => "published",
             "category" => "book", "price" => "12.5", "sku" => name.upcase,
             "image" => "/media/images/#{name}.jpg" }.merge(extra)
    path = File.join(RoeSitePaths::SITE_PRODUCTS_PATH, "#{name}.md")
    File.write(path, "---\n#{meta.to_yaml.sub(/\A---\n/, '')}---\n\nBody.\n")
    @created << path
    ContentSync.sync_file(path)
    Product.find_by("json_extract(metadata, '$.url_name') = ?", name)
  end

  test "a single product button shows the price by default" do
    product = write_product("pb-plain")

    html = ProductButtonRenderer.render({ "sku" => product.sku }, authenticated: true)

    assert_includes html, "snipcart-add-item"
    assert_includes html, "product-price", "a shopper expects a price beside a buy button"
  end

  test "show_price renders the price beside the button" do
    product = write_product("pb-priced")

    html = ProductButtonRenderer.render({ "sku" => product.sku, "show_price" => true }, authenticated: true)

    assert_includes html, '<span class="product-price">'
    assert_includes html, "12.50", "price is formatted to two decimals"
    assert_includes html, "snipcart-add-item"
    assert_operator html.index("product-price"), :<, html.index("snipcart-add-item"),
      "price precedes the button"
  end

  test "show_price accepts the builder's string value" do
    product = write_product("pb-string")

    html = ProductButtonRenderer.render({ "sku" => product.sku, "show_price" => "true" }, authenticated: true)

    assert_includes html, "product-price"
  end

  test "show_price false hides it" do
    product = write_product("pb-false")

    off = ProductButtonRenderer.render({ "sku" => product.sku, "show_price" => "false" }, authenticated: true)

    assert_not_includes off, "product-price"
    assert_includes off, "snipcart-add-item"
  end
end
