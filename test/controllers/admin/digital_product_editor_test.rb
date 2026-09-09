# frozen_string_literal: true

require "test_helper"

# The editor's half of digital goods: the toggle is on every product without
# being added, and the GUID field only exists alongside it.
class Admin::DigitalProductEditorTest < ActionDispatch::IntegrationTest
  GUID = "7235bd18-1745-488e-bdbb-dc4f424c1ca1"

  setup { sign_in_as(User.take) }

  # The edit action reads File.join(SITE_PATH, file_path), so the stored path is
  # relative to the site root.
  def product(extra = {})
    relative = File.join("products", "widget.md")
    absolute = File.join(RoeSitePaths::SITE_PATH, relative)
    meta = { "title" => "Widget", "url_name" => "widget", "status" => "draft",
             "sku" => "WIDG-1", "price" => 9.0, "category" => "music" }.merge(extra)

    # The editor renders from the file's frontmatter, not the record's column,
    # so the two have to agree.
    FileUtils.mkdir_p(File.dirname(absolute))
    File.write(absolute, "#{meta.to_yaml}---\nBody.\n")
    Product.create!(file_path: relative, content: "Body.", metadata: meta)
  end

  # It used to only appear if you knew to add it from the Add Field menu.
  test "the digital checkbox is on every product, unticked by default" do
    get edit_admin_product_path(product)

    assert_response :success
    assert_select "input[type=checkbox][data-metadata-field=?]", "digital", count: 1
    assert_select "input[type=checkbox][data-metadata-field=?][checked]", "digital", count: 0
  end

  test "an existing digital product shows the box ticked and its guid" do
    get edit_admin_product_path(product("digital" => true, "file_guid" => GUID))

    assert_select "input[type=checkbox][data-metadata-field=?][checked]", "digital"
    assert_select "[data-metadata-field=?][value=?]", "file_guid", GUID
  end

  # The reveal is the controller's job, but the row must not be in the file (or
  # the form) while the box is unticked — otherwise a stray guid rides along.
  test "an unticked product has no guid field at all" do
    get edit_admin_product_path(product)

    assert_select "[data-metadata-field=?]", "file_guid", count: 0
  end

  test "a guid left in the file is dropped while digital is off" do
    get edit_admin_product_path(product("digital" => false, "file_guid" => GUID))

    assert_select "[data-metadata-field=?]", "file_guid", { count: 0 },
      "the toggle decides; a leftover guid shouldn't reappear"
  end

  # Snipcart has no API for these, so the dashboard link is the whole of the
  # "seamless" part.
  test "the guid field links to the Snipcart dashboard" do
    get edit_admin_product_path(product("digital" => true, "file_guid" => GUID))

    assert_select "a[href=?]", "https://app.snipcart.com/dashboard/digital"
  end

  test "the digital-product controller is attached for products" do
    get edit_admin_product_path(product)

    assert_select "#metadata-container[data-controller*=?]", "digital-product"
  end

  # The warning used to be appended to the field row, which is a flex
  # container — it landed beside the input and squashed it. It belongs in a
  # footer under the field, sharing a line with the Snipcart link.
  test "the Snipcart link sits in a footer under the field" do
    get edit_admin_product_path(product("digital" => true, "file_guid" => GUID))

    assert_select "[data-digital-product-footer]" do
      assert_select "a[href=?]", "https://app.snipcart.com/dashboard/digital"
    end
    assert_select ".metadata-field-row > a[href*=?]", "snipcart.com", { count: 0 },
      "the link belongs in the footer, not as a sibling of the input"
  end

  # items-start lines a label up with the first line of a text input. A
  # checkbox is one small box, so it centres instead — but only checkbox rows,
  # or every other field would shift.
  test "only the checkbox row is centre-aligned" do
    get edit_admin_product_path(product)

    assert_select ".metadata-field-row.items-center[data-field-name=?]", "digital"
    assert_select ".metadata-field-row.items-start[data-field-name=?]", "sku", { count: 1 },
      "text fields keep top alignment"
  end
end
