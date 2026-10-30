require "test_helper"

# The Site Scripts section of the Themes page: Roe's shipped JS, seeded into
# site/javascript/ once and then the site's. A newer version is offered here
# and applied only by a click; an edited copy is never overwritten without a
# warning and can be kept beside the new one.
class Admin::ThemesScriptsTest < ActionDispatch::IntegrationTest
  SITE = SiteJavascript.site_dir

  setup do
    sign_in_as(users(:one))
    @backup = {}
    Dir.glob(File.join(SITE, "*")).each { |f| @backup[f] = File.read(f) if File.file?(f) } if File.directory?(SITE)
    FileUtils.rm_rf(SITE)
    FileUtils.mkdir_p(SITE)
  end

  teardown do
    FileUtils.rm_rf(SITE)
    FileUtils.mkdir_p(SITE)
    @backup.each { |f, c| File.write(f, c) }
  end

  def shipped(name) = File.read(File.join(SiteJavascript.source_dir, name))

  def install_old(name, edit: nil)
    content = shipped(name).sub(/Version: [\d.]+/, "Version: 0.0.1")
    content += "\n// #{edit}\n" if edit
    File.write(File.join(SITE, name), content)
  end

  test "the page lists every shipped script with its status" do
    File.write(File.join(SITE, "search.js"), shipped("search.js"))
    install_old("gallery.js")

    get admin_themes_path
    assert_response :success
    assert_includes response.body, "Site Scripts"
    assert_includes response.body, "search.js"
    assert_includes response.body, "Up to date"
    assert_includes response.body, "Update to v"
  end

  test "updating an untouched outdated script replaces it with the shipped one" do
    install_old("search.js")
    post update_script_admin_themes_path("search")

    assert_redirected_to admin_themes_path
    assert_equal shipped("search.js"), File.read(File.join(SITE, "search.js"))
    assert_empty Dir.glob(File.join(SITE, "search-*.js")), "no copy kept when none was asked for"
  end

  test "an edited script shows the warning and can be updated while keeping a copy" do
    install_old("search.js", edit: "my change")

    get admin_themes_path
    assert_includes response.body, "Edited"
    assert_includes response.body, "keep my copy"

    post update_script_admin_themes_path("search"), params: { keep_copy: "1" }
    assert_redirected_to admin_themes_path

    assert_equal shipped("search.js"), File.read(File.join(SITE, "search.js"))
    kept = File.join(SITE, "search-v0.0.1.js")
    assert File.exist?(kept), "previous copy saved beside the new one"
    assert_includes File.read(kept), "// my change"
  end

  test "download returns the site's copy" do
    install_old("search.js", edit: "mine")
    get download_script_admin_themes_path("search")

    assert_response :success
    assert_includes response.body, "// mine"
    assert_match(/attachment/, response.headers["Content-Disposition"])
  end

  test "download 404s for a file Roe doesn't ship, and for a missing site copy" do
    get download_script_admin_themes_path("evil")
    assert_response :not_found

    get download_script_admin_themes_path("search")
    assert_response :not_found
  end

  test "update refuses a file Roe doesn't ship" do
    post update_script_admin_themes_path("evil")
    assert_redirected_to admin_themes_path
    assert_not File.exist?(File.join(SITE, "evil.js"))
  end

  # --- UPDATE ALL --------------------------------------------------------------

  test "UPDATE ALL shows only when a script is outdated" do
    SiteJavascript.shipped_names.each { |n| File.write(File.join(SITE, n), shipped(n)) }
    get admin_themes_path
    assert_select "form[action=?]", update_all_scripts_admin_themes_path, count: 0

    install_old("search.js")
    get admin_themes_path
    assert_select "form[action=?]", update_all_scripts_admin_themes_path, count: 1
  end

  test "UPDATE ALL updates every outdated script, keeps edited copies, and leaves the rest" do
    install_old("search.js")
    install_old("gallery.js", edit: "my change")
    custom = File.join(SITE, "footnotes.js")
    File.write(custom, "// my own footnotes, no header\n")

    get admin_themes_path
    assert_includes response.body, "You&#39;ve changed gallery.js", "the confirm names the edited file"

    post update_all_scripts_admin_themes_path
    assert_redirected_to admin_themes_path

    assert_equal shipped("search.js"), File.read(File.join(SITE, "search.js"))
    assert_equal shipped("gallery.js"), File.read(File.join(SITE, "gallery.js"))
    kept = File.join(SITE, "gallery-v0.0.1.js")
    assert File.exist?(kept), "the edited copy is saved beside the new one"
    assert_includes File.read(kept), "// my change"
    assert_empty Dir.glob(File.join(SITE, "search-*.js")), "an untouched file gets no copy"
    assert_equal "// my own footnotes, no header\n", File.read(custom), "a custom file is never touched"
    assert_match(/gallery\.js and search\.js/, flash[:notice])
    assert_match(/gallery-v0\.0\.1\.js/, flash[:notice])
  end

  test "UPDATE ALL with nothing outdated says so and writes nothing" do
    File.write(File.join(SITE, "search.js"), shipped("search.js"))

    post update_all_scripts_admin_themes_path

    assert_redirected_to admin_themes_path
    assert_equal "All site scripts are already up to date.", flash[:notice]
    assert_equal [ "search.js" ], Dir.children(SITE)
  end
end
