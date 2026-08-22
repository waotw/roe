# frozen_string_literal: true

require "test_helper"

# Snipcart sells a downloadable file by matching a product to a file GUID from
# their dashboard. There's no API for those files — the GUID is a copy-paste —
# so the only thing Roe can do is carry it to every button and make a missing
# one obvious before a buyer hits it.
class DigitalProductTest < ActiveSupport::TestCase
  GUID = "7235bd18-1745-488e-bdbb-dc4f424c1ca1"

  def product(extra = {})
    Product.new(
      file_path: File.join(RoeSitePaths::SITE_PATH, "products", "widget.md"),
      content: "Body.",
      metadata: { "title" => "Widget", "url_name" => "widget", "status" => "published",
                  "sku" => "WIDG-1", "price" => 9.0 }.merge(extra)
    )
  end

  test "an ordinary product carries no digital attributes" do
    attrs = product.snipcart_attributes

    assert_not_includes attrs.keys, "data-item-file-guid"
    assert_not_includes attrs.keys, "data-item-shippable"
  end

  test "a digital product carries its file guid" do
    attrs = product("digital" => "true", "file_guid" => GUID).snipcart_attributes

    assert_equal GUID, attrs["data-item-file-guid"]
  end

  # Without this the cart asks for a shipping address to deliver a download to.
  test "a digital product is flagged unshippable" do
    attrs = product("digital" => "true", "file_guid" => GUID).snipcart_attributes

    assert_equal "false", attrs["data-item-shippable"]
  end

  # YAML gives a real boolean; the editor's select posts the string.
  test "the toggle reads as true either way" do
    assert product("digital" => true).digital?
    assert product("digital" => "true").digital?
    assert_not product("digital" => "false").digital?
    assert_not product.digital?
  end

  # The toggle is what decides. A guid left behind from an earlier edit must
  # not quietly turn shipping off on a physical product.
  test "a guid without the toggle does nothing" do
    attrs = product("file_guid" => GUID).snipcart_attributes

    assert_not_includes attrs.keys, "data-item-file-guid"
    assert_not_includes attrs.keys, "data-item-shippable"
  end

  # Better a product Snipcart rejects than one that sells and delivers nothing.
  test "digital with no guid emits no empty attribute" do
    attrs = product("digital" => "true", "file_guid" => "  ").snipcart_attributes

    assert_not_includes attrs.keys, "data-item-file-guid"
  end

  test "the crawler url can be overridden, and quantity is opt-in" do
    attrs = product.snipcart_attributes(url: "https://shop.example.com/store/widget", quantity: 2)

    assert_equal "https://shop.example.com/store/widget", attrs["data-item-url"]
    assert_equal 2, attrs["data-item-quantity"]
    assert_not_includes product.snipcart_attributes.keys, "data-item-quantity"
  end

  # These were built by hand in three places that had already drifted. A field
  # added to two of three would validate on the product's own page and fail
  # from a grid — Snipcart crawls data-item-url and matches data-item-id.
  test "every button builds from the same attributes" do
    digital = product("digital" => "true", "file_guid" => GUID)
    digital.save!

    rendered = ProductButtonRenderer.new({ "sku" => "WIDG-1" }).render

    assert_includes rendered, %(data-item-file-guid="#{GUID}")
    assert_includes rendered, %(data-item-shippable="false")
    assert_includes rendered, "snipcart-add-item", "the class Snipcart's crawler looks for"
  end

  # The third emitter: a product grid built its attributes as raw strings, the
  # furthest from the other two. A digital good bought from a grid has to carry
  # the same GUID as one bought from its own page.
  test "a product grid carries the digital attributes too" do
    product("digital" => "true", "file_guid" => GUID).save!
    SnipcartConfig.stubs(:current).returns(stub(connected?: true))

    html = Page.new(
      file_path: File.join(RoeSitePaths::SITE_PATH, "pages", "store.md"),
      content: "```collection\nsource: products\ntemplate: grid\n```",
      metadata: { "title" => "Store", "status" => "published" }
    ).to_html

    assert_includes html, "btn-grid", "the grid button rendered"
    assert_includes html, %(data-item-file-guid="#{GUID}")
    assert_includes html, %(data-item-shippable="false")
  end

  # ── The editor ─────────────────────────────────────────────────────────────

  # Selling a file should be a checkbox on every product, not something you
  # have to know to add from a menu.
  test "digital is a checkbox on the product schema" do
    assert_equal :checkbox, ContentMetadataSchema.fields_for("product")["digital"][:type]
  end

  test "file_guid is a known product field" do
    assert_equal :text, ContentMetadataSchema.fields_for("product")["file_guid"][:type]
  end

  # Neither belongs in the file without the other.
  test "posts and pages get neither field" do
    %w[post page].each do |type|
      assert_nil ContentMetadataSchema.fields_for(type)["digital"], "#{type} should have no digital field"
      assert_nil ContentMetadataSchema.fields_for(type)["file_guid"]
    end
  end

  # ── No button when it can't deliver ────────────────────────────────────────
  #
  # The two failures aren't symmetrical. Snipcart refuses a *wrong* GUID at
  # checkout, so nobody is charged. It accepts a *missing* one without
  # complaint — Roe drops the empty attribute, so Snipcart sees an ordinary
  # non-shippable product, takes the money and has nothing to send. Neither
  # should be buyable.

  test "a digital product with no guid can't deliver" do
    assert_not product("digital" => "true").deliverable?
    assert_equal :missing_file_guid, product("digital" => "true").delivery_problem
  end

  test "a digital product with a malformed guid can't deliver" do
    p = product("digital" => "true", "file_guid" => "not-a-guid")

    assert_not p.deliverable?
    assert_equal :malformed_file_guid, p.delivery_problem
  end

  test "a complete digital product, and any physical product, can" do
    assert product("digital" => "true", "file_guid" => GUID).deliverable?
    assert product.deliverable?
    assert product("file_guid" => "junk").deliverable?, "a stray guid on a physical product is inert"
  end

  # The `button` block.
  test "the button block renders no add-to-cart for an undeliverable product" do
    product("digital" => "true", "file_guid" => "").save!

    html = ProductButtonRenderer.new({ "sku" => "WIDG-1" }).render

    assert_not_includes html, "snipcart-add-item", "there must be no way to add it"
    assert_includes html, "Not available to buy"
  end

  # The product grid.
  test "the grid renders no add-to-cart for an undeliverable product" do
    product("digital" => "true", "file_guid" => "nope", "status" => "published").save!
    SnipcartConfig.stubs(:current).returns(stub(connected?: true))

    html = Page.new(
      file_path: File.join(RoeSitePaths::SITE_PATH, "pages", "store.md"),
      content: "```collection\nsource: products\ntemplate: grid\n```",
      metadata: { "title" => "Store", "status" => "published" }
    ).to_html

    assert_not_includes html, "snipcart-add-item",
      "a grid mustn't sell what the product page refuses to"
    assert_includes html, "Not available"
  end

  # And it can't be published into that state in the first place. The base
  # fixture is missing category/image, which would flag on their own — fill
  # them in so the GUID is the only thing under test.
  test "publishing is blocked while it can't deliver" do
    # Everything else has to be genuinely valid — including the image existing
    # on disk — or publish_warnings? would be true whatever the GUID says, and
    # the test would pass without proving anything.
    image = File.join(RoeSitePaths::SITE_PATH, "media", "images", "w.jpg")
    FileUtils.mkdir_p(File.dirname(image))
    File.write(image, "x")
    complete = { "category" => "music", "image" => "/media/images/w.jpg", "digital" => "true" }

    assert_not product(complete.merge("file_guid" => GUID)).publish_warnings?,
      "a complete digital product publishes normally"

    assert product(complete.merge("file_guid" => "")).publish_warnings?
    assert product(complete.merge("file_guid" => "nope")).publish_warnings?
  end

  # The editor's live check and the server's gate have to agree, or one will
  # accept what the other rejects.
  test "the browser check uses the same GUID pattern as the server" do
    js = File.read(Rails.root.join("app/javascript/controllers/digital_product_controller.js"))
    js_pattern = js[/static UUID = \/(.+?)\/i;/, 1]
    assert js_pattern.present?, "could not find the UUID pattern in the controller"

    # Compare the bodies; only the anchors differ (\A..\z in Ruby, ^..$ in JS).
    strip_anchors = ->(src) { src.sub(/\A(\\A|\^)/, "").sub(/(\\z|\$)\z/, "") }

    assert_equal strip_anchors.call(Product::FILE_GUID_FORMAT.source),
                 strip_anchors.call(js_pattern),
                 "the editor's check and the server's gate have drifted apart"
  end
end
