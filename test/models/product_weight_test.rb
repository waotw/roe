require "test_helper"

# Snipcart: "The weight in grams of the product. Mandatory if you use any
# integrated shipping provider we support." Integers only, no decimals — so a
# site with no weight can't quote postage at all.
class ProductWeightTest < ActiveSupport::TestCase
  def product(**meta)
    Product.new(metadata: { "title" => "Book", "sku" => "BK-1", "price" => 20.0 }.merge(meta.transform_keys(&:to_s)))
  end

  test "a weight is read as whole grams" do
    assert_equal 500, product(weight: "500").weight
  end

  test "it reaches Snipcart as data-item-weight" do
    attrs = product(weight: "500").snipcart_attributes(url: "/store/book")

    assert_equal 500, attrs["data-item-weight"]
  end

  # Snipcart drops decimals silently, and the shop owner finds out from a wrong
  # postage quote rather than an error.
  # #weight rounded on read, so the file kept 499.6 while the HTML said 500 —
  # the file and the shop disagreeing with nothing to say which counted.
  test "the saved file stores what Snipcart will actually receive" do
    yaml = Product.format_metadata_yaml({ "title" => "Book", "weight" => "499.6" })

    assert_match(/^weight: 500$/, yaml)
  end

  test "a weight that produces no attribute is stored blank, not as typed" do
    [ "0", "-5", "heavy", "" ].each do |input|
      yaml = Product.format_metadata_yaml({ "title" => "Book", "weight" => input })

      assert_match(/^weight: ""$/, yaml,
        "#{input.inspect} sends no data-item-weight, so the file shouldn't claim one")
    end
  end

  test "normalising doesn't disturb the rest of the metadata" do
    yaml = Product.format_metadata_yaml({ "title" => "Book", "sku" => "BK-1", "weight" => "500.4" })

    assert_match(/^title: /, yaml)
    assert_match(/^sku: /, yaml)
    assert_match(/^weight: 500$/, yaml)
  end

  test "a decimal is rounded rather than passed through" do
    assert_equal 500, product(weight: "499.6").weight
    assert_equal 2, product(weight: "2.4").weight
  end

  test "no weight sends no attribute" do
    attrs = product.snipcart_attributes(url: "/store/book")

    assert_not attrs.key?("data-item-weight")
  end

  # Zero would quote free shipping rather than refuse to quote, which is worse
  # than having no weight at all.
  test "zero and negatives count as absent" do
    assert_nil product(weight: "0").weight
    assert_nil product(weight: "-5").weight
    assert_not product(weight: "0").snipcart_attributes(url: "/x").key?("data-item-weight")
  end

  test "blank and junk are ignored" do
    assert_nil product(weight: "").weight
    assert_nil product(weight: "   ").weight
    assert_nil product(weight: "heavy").weight
  end

  # A digital product doesn't need one, but setting both isn't an error —
  # Snipcart ignores weight on a non-shippable item.
  test "a digital product with a weight still sends both, harmlessly" do
    p = product(weight: "500", digital: true, file_guid: "7235bd18-1745-488e-bdbb-dc4f424c1ca1")
    attrs = p.snipcart_attributes(url: "/store/book")

    assert_equal 500, attrs["data-item-weight"]
    assert_equal "false", attrs["data-item-shippable"]
  end

  test "the field is offered in the product editor, with the unit visible" do
    field = ContentMetadataSchema.fields_for("product")["weight"]

    assert field, "weight should be an editable product field"
    assert_equal "grams", field[:suffix],
      "the unit has to be visible — pounds or kilos here quote silently wrong postage"
  end

  # Label width sets the whole column (longest label + 1), so carrying the unit
  # in the label would widen every row on every product form.
  test "the label doesn't widen the column for every other field" do
    fields = ContentMetadataSchema.fields_for("product")

    assert_equal "weight", fields["weight"][:label]
    assert_operator fields["weight"][:label].length, :<=,
                    fields.values.map { |c| c[:label].to_s.length }.max
  end

  # A placeholder long enough to explain something is wider than the field, and
  # vanishes as soon as you type.
  test "the explanation is a note, not an oversized placeholder" do
    field = ContentMetadataSchema.fields_for("product")["weight"]

    assert field[:note].present?, "the explanation belongs under the field"
    assert_operator field[:hint].to_s.length, :<, 10, "the placeholder should be an example, not a sentence"
  end
end
