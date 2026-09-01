require "test_helper"

# A note under a field has to line up with the field, not with the label. The
# label's width is .metadata-label — the ch value plus 1rem for its own padding
# — so a spacer built from the ch value alone leaves the note short.
class MetadataNoteTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    @dir = File.join(RoeSitePaths::SITE_PATH, "products")
    FileUtils.mkdir_p(@dir)
    @path = File.join(@dir, "zz-note-test.md")
    File.write(@path, <<~MD)
      ---
      title: "ZZ Note Test"
      url_name: "zz-note-test"
      status: "draft"
      sku: "ZZ-NOTE-1"
      price: 10.0
      group: "zz-note-group"
      show_sidebar: "true"
      ---

      body
    MD
    @product = Product.create_or_update_from_file(@path)
  end

  teardown do
    FileUtils.rm_f(@path)
    Product.where(file_path: RoeSitePaths.normalize(@path)).destroy_all
  end

  test "weight appears on a product that never had it" do
    get edit_admin_product_path(@product)

    assert_response :success
    assert_select "[data-metadata-field='weight']"
  end

  test "the unit renders after the field, not inside the label" do
    get edit_admin_product_path(@product)

    assert_match "grams", response.body
    assert_select "label", text: /weight \(grams\)/, count: 0
  end

  test "the note renders under the field" do
    get edit_admin_product_path(@product)

    assert_match "Needed for Snipcart shipping rates", response.body
  end

  # Alignment is structural: the note is a sibling of the input inside the
  # field's own column, so it starts where the field starts without anything
  # having to replicate the label's width.
  test "the note shares a column with the field it describes" do
    get edit_admin_product_path(@product)

    assert_select "div[data-field-name='weight'] > div.flex-1" do
      assert_select "input[data-metadata-field='weight']", count: 1
      assert_select "> p", text: /Whole grams/, count: 1
    end
  end

  # Booleans that mean the same thing absent or false are checkboxes now; a
  # two-option dropdown was pretending to be a toggle.
  test "boolean fields render as checkboxes, not selects" do
    get edit_admin_product_path(@product)

    assert_select "input[type=checkbox][data-metadata-field='primary']", count: 1
    assert_select "select[data-metadata-field='primary']", count: 0
  end

  # Now that `true` forces the sidebar on, two states are enough: the file
  # always wins, and an absent field means "follow the scope".
  test "show_sidebar is a checkbox now that true means something" do
    get edit_admin_product_path(@product)

    assert_select "input[type=checkbox][data-metadata-field='show_sidebar']", count: 1
    assert_select "select[data-metadata-field='show_sidebar']", count: 0
  end

  test "primary's explanation is a note, not dropdown instructions" do
    field = ContentMetadataSchema.fields_for("product")["primary"]

    assert_equal :checkbox, field[:type]
    assert_match(/only one product/i, field[:note].to_s)
    assert_nil field[:options], "a checkbox has no options to choose between"
  end

  # The old approach — a spacer copying the label's width — is gone.
  test "no hand-copied spacer is used to indent the note" do
    get edit_admin_product_path(@product)

    assert_select "div.metadata-label[aria-hidden='true']", count: 0
  end
end
