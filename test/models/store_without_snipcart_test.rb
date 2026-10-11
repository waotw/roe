# frozen_string_literal: true

require "test_helper"

# A store without a cart: products shown, and bought somewhere else — a book on
# Amazon, say. `snipcart.enabled: false` in store.yml turns Snipcart off, and
# `collection_buttons` decides where a product collection's button goes.
#
# Run against a real store.yml rather than stubs, so the settings are read the
# way the site reads them (a missing key, a quoted boolean).
class StoreWithoutSnipcartTest < ActiveSupport::TestCase
  STORE_YML = SiteConfig::FEATURES_PATH.join("store.yml")

  setup do
    @created = []
    @store_before = File.exist?(STORE_YML) ? File.read(STORE_YML) : nil
    FileUtils.mkdir_p(RoeSitePaths::SITE_PRODUCTS_PATH)
  end

  teardown do
    @created.each { |f| File.delete(f) if File.exist?(f) }
    if @store_before
      File.write(STORE_YML, @store_before)
    else
      File.delete(STORE_YML) if File.exist?(STORE_YML)
    end
    reload_store
  end

  def store(yaml)
    FileUtils.mkdir_p(STORE_YML.dirname)
    File.write(STORE_YML, "enabled: true\ncurrency: usd\n#{yaml}")
    reload_store
  end

  def reload_store
    SiteConfig.sync_from_file("features/store") if File.exist?(STORE_YML)
    Rails.cache.clear
  end

  def write_product(name, extra = {})
    meta = { "title" => name.tr("-", " "), "url_name" => name, "status" => "published",
             "category" => "book", "image" => "/media/images/#{name}.jpg" }.merge(extra)
    path = File.join(RoeSitePaths::SITE_PRODUCTS_PATH, "#{name}.md")
    File.write(path, "---\n#{meta.to_yaml.sub(/\A---\n/, '')}---\n\nBody.\n")
    @created << path
    ContentSync.sync_file(path)
    Product.find_by("json_extract(metadata, '$.url_name') = ?", name)
  end

  # A grid of one product, rendered the way a page renders a collection block.
  def grid_for(product)
    Page.new(content: "x").send(:render_product_grid, [ product ], {})
  end

  # --- the switches ----------------------------------------------------------

  test "Snipcart is on unless store.yml turns it off" do
    store("")
    assert SiteFeature.snipcart_enabled?, "a store written before the setting keeps its cart"

    store("snipcart:\n  enabled: false\n")
    assert_not SiteFeature.snipcart_enabled?

    store("snipcart:\n  enabled: \"false\"\n")
    assert_not SiteFeature.snipcart_enabled?, "a quoted false from a hand-edited file counts"
  end

  test "collection buttons go to the cart by default, and to the page when asked" do
    store("")
    assert_not SiteFeature.collection_buttons_link_to_page?

    store("collection_buttons:\n  link_to_product_page: true\n")
    assert SiteFeature.collection_buttons_link_to_page?
  end

  test "without Snipcart, collection buttons always go to the page" do
    store("snipcart:\n  enabled: false\ncollection_buttons:\n  link_to_product_page: false\n")
    assert SiteFeature.collection_buttons_link_to_page?, "there's no cart to add to"
  end

  # --- product collections ---------------------------------------------------

  test "a collection button adds to the cart by default" do
    store("")
    html = grid_for(write_product("sws-cart", "price" => "10", "sku" => "SWS-CART"))

    assert_includes html, "snipcart-add-item"
    assert_includes html, ">Add to Cart</button>"
  end

  test "link_to_product_page sends the collection button to the product page" do
    store("collection_buttons:\n  link_to_product_page: true\n")
    html = grid_for(write_product("sws-page", "price" => "10", "sku" => "SWS-PAGE"))

    assert_not_includes html, "snipcart-add-item"
    assert_includes html, %(<a href="/store/sws-page" class="btn-primary btn-grid">View</a>)
  end

  test "button text names the button either way" do
    store("collection_buttons:\n  text: \"See the book\"\n")
    cart = grid_for(write_product("sws-text-cart", "price" => "10", "sku" => "SWS-TC"))
    assert_includes cart, ">See the book</button>"

    store("collection_buttons:\n  link_to_product_page: true\n  text: \"See the book\"\n")
    page = grid_for(write_product("sws-text-page", "price" => "10", "sku" => "SWS-TP"))
    assert_includes page, ">See the book</a>"
  end

  test "without Snipcart a product with no SKU still gets a button to its page" do
    store("snipcart:\n  enabled: false\n")
    html = grid_for(write_product("sws-nosku"))

    assert_includes html, %(href="/store/sws-nosku" class="btn-primary btn-grid")
  end

  test "a product with no price shows no price, rather than $0.00" do
    store("snipcart:\n  enabled: false\n")
    html = grid_for(write_product("sws-noprice"))

    assert_includes html, %(<span class="grid-item-price"></span>), "the cell stays, empty"
    assert_not_includes html, "$0.00"
  end

  test "an undeliverable product in a grid still closes its card" do
    store("")
    html = grid_for(write_product("sws-undeliv", "price" => "5", "sku" => "SWS-U", "digital" => true))

    assert_includes html, "Not available"
    assert_equal html.scan("<div").size, html.scan("</div>").size, "every card is closed"
  end

  # --- the button block ------------------------------------------------------

  test "without Snipcart a button elsewhere links to the product page" do
    store("snipcart:\n  enabled: false\n")
    product = write_product("sws-block", "sku" => "SWS-BLOCK")

    html = ProductButtonRenderer.render({ "sku" => "SWS-BLOCK", "text" => "Get the book" }, authenticated: true)

    assert_not_includes html, "snipcart-add-item"
    assert_includes html, %(href="#{product.public_url}")
    assert_includes html, "Get the book"
  end

  test "without Snipcart a button can name its product by url_name" do
    store("snipcart:\n  enabled: false\n")
    write_product("sws-by-name")

    html = ProductButtonRenderer.render({ "sku" => "sws-by-name" }, authenticated: true)

    assert_includes html, %(href="/store/sws-by-name")
    assert_includes html, ">View</a>", "an unset label reads as a link, not a cart"
  end

  test "a template's Add to Cart becomes View on a link" do
    store("snipcart:\n  enabled: false\n")
    write_product("sws-atc")

    html = ProductButtonRenderer.render({ "sku" => "sws-atc", "text" => "Add to Cart" }, authenticated: true)

    assert_includes html, ">View</a>"
  end

  test "without Snipcart a button on its own product's page renders nothing" do
    store("snipcart:\n  enabled: false\n")
    product = write_product("sws-self", "price" => "9")

    html = ProductButtonRenderer.render({}, current_product: product, authenticated: true)

    assert_not_includes html, "<a "
    assert_not_includes html, "snipcart-add-item"
  end

  # A variant list lays out on a three-column grid (name, price, button). A
  # row missing a cell pushes every cell after it into the wrong column.
  test "every variant row keeps all three cells, with or without a price or button" do
    store("snipcart:\n  enabled: false\n")
    here = write_product("sws-var-a", "group" => "sws-var", "variant" => "Paperback", "price" => "5", "primary" => true)
    write_product("sws-var-b", "group" => "sws-var", "variant" => "Ebook")

    html = ProductButtonRenderer.render({}, current_product: here, authenticated: true)
    rows = Nokogiri::HTML.fragment(html).css("li.product-variant-item")

    assert_equal 2, rows.size
    rows.each { |row| assert_equal 3, row.element_children.size, row.to_html }
    assert_includes html, %(class="variant-current"), "the variant you're on keeps a cell in the button's place"
  end

  test "a grid card keeps its price cell even with no price, so the button stays right" do
    store("snipcart:\n  enabled: false\n")
    html = grid_for(write_product("sws-cell"))
    footer = Nokogiri::HTML.fragment(html).at_css(".grid-item-footer")

    assert_equal 2, footer.element_children.size
    assert_equal "", footer.at_css(".grid-item-price").text.strip
  end

  # --- requirements and warnings ---------------------------------------------

  test "without Snipcart, SKU and price aren't required" do
    store("snipcart:\n  enabled: false\n")
    product = write_product("sws-req")

    assert_empty product.missing_required_fields
    # needs_attention? also checks the image file exists, which this test's
    # made-up path doesn't — so ask only about fields here.
  end

  test "with Snipcart, SKU and price are still required" do
    store("")
    product = write_product("sws-req-on")

    assert_includes product.missing_required_fields, "sku"
    assert_includes product.missing_required_fields, "price"
  end

  test "without Snipcart, an undeliverable digital product isn't a warning" do
    store("snipcart:\n  enabled: false\n")
    product = write_product("sws-digital", "digital" => true, "image" => "")
    product.metadata["image"] = "/media/images/x.jpg"
    product.stubs(:missing_media_refs).returns([])

    assert_not product.publish_warnings?, "delivery is Snipcart's question"
  end

  test "without Snipcart there's no orange dot for it" do
    store("snipcart:\n  enabled: false\n")
    assert_not SiteFeature.snipcart_unconfigured?
  end

  test "without Snipcart the editor stops asking for Snipcart fields" do
    store("snipcart:\n  enabled: false\n")
    fields = ContentMetadataSchema.fields_for("product")

    assert_not fields["sku"][:required]
    assert_not fields["price"][:required]
    %w[digital file_guid weight].each do |name|
      assert_equal false, fields[name][:available], "#{name} leaves the Add Field menu"
    end
    assert_equal %w[category image], ContentMetadataSchema.create_fields_for("product").map { |f| f[:name] }
  end

  test "a new product without Snipcart starts with no price and no buy button" do
    store("snipcart:\n  enabled: false\n")
    metadata, body = ContentTemplate.frontmatter_for("product", "title" => "A Book")

    assert_nil metadata["price"]
    assert_not_includes body, "```button"
  end
end
