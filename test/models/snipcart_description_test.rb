require "test_helper"

# A cart holding three sizes of the same tee showed three identical "Lab Tee"
# rows: the size lives in `variant` and never reached Snipcart. Variant files
# also tend to carry an empty description — the group's copy sits on the
# primary — so only the primary sent one at all.
class SnipcartDescriptionTest < ActiveSupport::TestCase
  def product(**meta)
    Product.new(metadata: { "title" => "Lab Tee", "price" => 18.0 }.merge(meta.transform_keys(&:to_s)))
  end

  def create_group!
    @primary = product(sku: "LAB-TEE-S", variant: "small", primary: true,
                       group: "lab tee", description: "A soft cotton tee.",
                       url_name: "lab-tee", status: "published")
    @medium  = product(sku: "LAB-TEE-M", variant: "medium", primary: false,
                       group: "lab tee", description: "",
                       url_name: "lab-tee-md", status: "published")
    [ @primary, @medium ].each { |p| p.file_path = "products/#{p.sku}.md"; p.save! }
  end

  test "the variant leads the description" do
    create_group!
    assert_equal "small — A soft cotton tee.", @primary.snipcart_description
  end

  # The bug: medium and large sent no description at all.
  test "a variant with no description inherits the group's" do
    create_group!
    assert_equal "medium — A soft cotton tee.", @medium.snipcart_description
  end

  test "the inherited copy reaches the button attributes" do
    create_group!
    attrs = @medium.snipcart_attributes(url: "/store/lab-tee-md", quantity: 1)

    assert_equal "medium — A soft cotton tee.", attrs["data-item-description"],
      "every variant should carry a description, not just the primary"
  end

  test "a variant's own description wins over the group's" do
    create_group!
    own = product(sku: "LAB-TEE-L", variant: "large", primary: false, group: "lab tee",
                  description: "Roomier cut.", url_name: "lab-tee-lg", status: "published")

    assert_equal "large — Roomier cut.", own.snipcart_description
  end

  test "a product with no variant is unchanged" do
    assert_equal "A mug.", product(sku: "MUG", description: "A mug.").snipcart_description
  end

  test "a variant with no description anywhere still names itself" do
    assert_equal "large", product(sku: "X", variant: "large", group: "nothing").snipcart_description
  end

  # Nothing to say means the attribute is dropped, as before.
  test "no variant and no description sends nothing" do
    p = product(sku: "Y")
    assert_nil p.snipcart_description
    assert_not p.snipcart_attributes(url: "/store/y").key?("data-item-description")
  end
end
