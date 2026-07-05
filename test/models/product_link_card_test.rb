# frozen_string_literal: true

require "test_helper"

# A product-link card is a live post-link-style card pointed at a product — it
# resolves the product and renders its details (title, price, description),
# never a frozen snapshot.
class ProductLinkCardTest < ActiveSupport::TestCase
  def make_product(price: 9, description: "A great gadget.")
    Product.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "products", "widget.md"),
      content: "Body copy.",
      metadata: {
        "title" => "Test Widget", "url_name" => "test-widget", "status" => "published",
        "price" => price, "description" => description
      }
    )
  end

  def host_post(body)
    Post.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "host.md"),
      content: body,
      metadata: { "title" => "Host", "status" => "published" }
    )
  end

  def render_card(extra = "")
    make_product
    host_post("```card\ntype: product-link\nproduct: test-widget\n#{extra}```").to_html
  end

  test "renders a live card from the referenced product" do
    out = render_card

    assert_includes out, "Test Widget", "should pull the product's title"
    assert_includes out, "/store/test-widget", "should link to the product page"
    assert_includes out, "View product", "product-appropriate link text"
  end

  test "shows the product's price" do
    assert_includes render_card, "$9.00"
  end

  test "shows the product's description by default (small style)" do
    assert_includes render_card, "A great gadget."
  end

  test "show_description: false hides the description" do
    refute_includes render_card("show_description: false\n"), "A great gadget."
  end

  test "an explicit description overrides the product's" do
    out = render_card("description: Custom blurb.\n")
    assert_includes out, "Custom blurb."
    refute_includes out, "A great gadget."
  end
end
