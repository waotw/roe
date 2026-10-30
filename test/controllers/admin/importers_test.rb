require "test_helper"

# The Tools menu has one Imports entry; the Imports page links to each
# importer, and each importer links back to it.
class Admin::ImportersTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:one)) }

  test "the Imports page links to all four importers" do
    get admin_importers_path
    assert_response :success

    [ admin_imports_path, admin_feed_imports_path, admin_file_imports_path, admin_media_imports_path ].each do |path|
      assert_select "main a[href=?]", path
    end
  end

  test "the Tools menu has Imports, Images & Video and Developer Tools, not each importer" do
    get admin_importers_path

    assert_select "[data-dropdown-target=menu] a[href=?]", admin_importers_path, text: "Imports"
    assert_select "[data-dropdown-target=menu] a[href=?]", admin_dependencies_path, text: "Images & Video"
    assert_select "[data-dropdown-target=menu] a[href=?]", admin_development_dependencies_path, text: "Developer Tools"
    assert_select "[data-dropdown-target=menu] a[href=?]", admin_feed_imports_path, count: 0
    assert_select "[data-dropdown-target=menu] a[href=?]", admin_imports_path, count: 0
  end

  test "each importer links back to the Imports page" do
    [ admin_imports_path, admin_feed_imports_path, admin_file_imports_path, admin_media_imports_path ].each do |path|
      get path
      assert_response :success, "#{path} didn't load"
      assert_select "main a[href=?]", admin_importers_path, { text: /Imports/ }, "#{path} has no link back to Imports"
    end
  end
end
