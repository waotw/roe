require "test_helper"

# SAVE AS… in the theme editor: the editor's text becomes a new theme file
# beside the original, marked as the site's own so updates leave it alone.
class Admin::ThemeSaveAsTest < ActionDispatch::IntegrationTest
  DIR = Admin::ThemesController::USER_THEME_DIR
  SOURCE = "zz-saveas-source"

  setup do
    sign_in_as(users(:one))
    FileUtils.mkdir_p(DIR)
    File.write(DIR.join("#{SOURCE}.css"), File.read(Rails.root.join("app/themes/default.css")))
    @made = []
  end

  teardown do
    FileUtils.rm_f(DIR.join("#{SOURCE}.css"))
    @made.each { |name| FileUtils.rm_f(DIR.join("#{name}.css")) }
  end

  def save_as(name, content)
    post save_as_admin_theme_path(SOURCE), params: { name: name, content: content }, as: :json
  end

  test "writes the editor's text as a new custom theme and leaves the original alone" do
    original = File.read(DIR.join("#{SOURCE}.css"))
    edited = original.sub("/* ==== CUSTOM CODE ==== */", "/* ==== CUSTOM CODE ==== */\n.zz { color: red; }")
    @made << "zz-saveas-dark"

    save_as("ZZ SaveAs Dark", edited)

    assert_response :success
    assert_equal({ "saved" => true, "name" => "zz-saveas-dark", "url" => edit_admin_theme_path("zz-saveas-dark") }, response.parsed_body)
    assert_equal original, File.read(DIR.join("#{SOURCE}.css"))

    copy = DIR.join("zz-saveas-dark.css")
    assert_includes File.read(copy), ".zz { color: red; }"
    header = ThemeInspector.parse_header(copy)
    assert_equal "ZZ SaveAs Dark", header.name
    assert_equal "1.0.0", header.version
    assert_nil header.fingerprint
    assert_match(/Based on: Default \d/, File.read(copy))
    assert_equal :custom, ThemeInspector.status(bundled_path: Rails.root.join("app/themes/default.css"), installed_path: copy)
    assert_equal 1, File.read(copy).scan("THEME INFO").size
  end

  # Theme names come from the URL. The route already refuses dots in :id,
  # and the path helper strips folders as well, so a name can't reach
  # outside the theme folder.
  test "theme paths keep only the file name" do
    path = Admin::ThemesController.new.send(:theme_css_path, DIR, "../../config/#{SOURCE}")
    assert_equal DIR.join("#{SOURCE}.css"), path
  end

  test "refuses a name that's taken or has no letters" do
    save_as("Default", "body {}")
    assert_response :unprocessable_entity
    assert_match(/already a theme/, response.parsed_body["error"])

    save_as("  ***  ", "body {}")
    assert_response :unprocessable_entity
    assert_match(/letter or number/, response.parsed_body["error"])
  end

  test "a file without Roe's header gets one added above its CSS" do
    @made << "zz-saveas-plain"
    save_as("ZZ SaveAs Plain", "body { color: blue; }\n")

    text = File.read(DIR.join("zz-saveas-plain.css"))
    assert text.start_with?("/* ==== THEME INFO ====")
    assert text.end_with?("body { color: blue; }\n")
  end

  test "the editor page uses CodeMirror 6 modules, not the old CodeMirror script" do
    get edit_admin_theme_path(SOURCE)

    assert_response :success
    assert_select "#theme-editor[data-controller~=css-editor][data-controller~=theme-inspector]"
    assert_select "script[src*='codemirror.min']", 0
    assert_includes response.body, "theme_editor/editor"
  end
end
