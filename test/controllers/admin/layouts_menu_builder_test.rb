require "test_helper"

class Admin::LayoutsMenuBuilderTest < ActionDispatch::IntegrationTest
  # Another test can delete site/layout/. Recreate it, and take away the header
  # this test writes: a header.md left behind outranks the navigation.md that
  # other tests (search, say) write, so they'd read the wrong menu.
  setup do
    sign_in_as(users(:one))
    FileUtils.mkdir_p(LayoutFiles.dir)
    @header_existed = LayoutFiles.exist?("header")
  end

  teardown { FileUtils.rm_f(LayoutFiles.path("header")) unless @header_existed }

  test "the layout editor renders the navigation builder" do
    File.write(LayoutFiles.path("header"), "# Header\n") unless LayoutFiles.exist?("header")
    get "/admin/layout/header/edit"
    assert_response :success
    assert_includes response.body, 'data-controller="site-links"'
    assert_includes response.body, "Add Navigation"
    assert_includes response.body, 'data-site-links-target="toggleButton"'
    assert_includes response.body, 'data-site-links-target="collectionHint"'
    assert_not_includes response.body, "toggle-links", "the old Show Links panel is gone"
  end

  test "returns the link list with guesses as JSON, writing nothing" do
    header = LayoutFiles.path("header")
    before = File.exist?(header) ? File.read(header) : nil

    post admin_layouts_menu_builder_path,
      params: { content: "- [About](/about)\n- [Feed](/feed.xml)" }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "application/json" }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 0, body["start"]
    assert_equal 1, body["finish"]
    assert_equal 2, body["rows"].size
    assert_equal "Feed", body["rows"][1]["text"]
    assert body["pages"].is_a?(Array)

    after = File.exist?(header) ? File.read(header) : nil
    assert_equal before.to_s, after.to_s, "the builder never writes the layout file"
  end

  test "says so when there is no list" do
    post admin_layouts_menu_builder_path,
      params: { content: "# no links here" }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "application/json" }

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["error"], "No list of links"
  end
end
