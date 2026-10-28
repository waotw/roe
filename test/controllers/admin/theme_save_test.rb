require "test_helper"

# The CSS editor saves in the background (asking for JSON) so the page
# doesn't reload and the writer keeps their place. A plain form post still
# redirects back to the editor, as before.
class Admin::ThemeSaveTest < ActionDispatch::IntegrationTest
  THEME = "zz-save-test"
  FILE = Admin::ThemesController::USER_THEME_DIR.join("#{THEME}.css")

  setup do
    sign_in_as(users(:one))
    FileUtils.mkdir_p(FILE.dirname)
    File.write(FILE, "body { color: red; }\n")
  end

  teardown { FileUtils.rm_f(FILE) }

  test "a background save writes the file and answers with JSON, no redirect" do
    patch admin_theme_path(THEME), params: { content: "body { color: blue; }\n" }, as: :json

    assert_response :success
    assert_equal({ "saved" => true }, response.parsed_body)
    assert_equal "body { color: blue; }\n", File.read(FILE)
  end

  test "a plain form save still redirects back to the editor" do
    patch admin_theme_path(THEME), params: { content: "body { color: green; }\n" }

    assert_redirected_to edit_admin_theme_path(THEME)
    assert_equal "body { color: green; }\n", File.read(FILE)
  end
end
