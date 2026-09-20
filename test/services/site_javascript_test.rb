require "test_helper"

# Roe's front-end JS is seeded into site/javascript/ once and then belongs
# to the site. Roe never rewrites or renames it on boot; updates are offered
# on the Updates page through ShippedFileInspector. Resolution: site copy
# first, shipped source second.
class SiteJavascriptTest < ActiveSupport::TestCase
  SITE = SiteJavascript.site_dir

  setup do
    @backup = {}
    Dir.glob(File.join(SITE, "**", "*")).each { |f| @backup[f] = File.read(f) if File.file?(f) } if File.directory?(SITE)
    FileUtils.rm_rf(SITE)
  end

  teardown do
    FileUtils.rm_rf(SITE)
    @backup.each do |f, c|
      FileUtils.mkdir_p(File.dirname(f))
      File.write(f, c)
    end
  end

  test "path prefers the site copy, falls back to the shipped source" do
    assert_equal File.join(SiteJavascript.source_dir, "search.js"), SiteJavascript.path("search.js")

    FileUtils.mkdir_p(SITE)
    site_copy = File.join(SITE, "search.js")
    File.write(site_copy, "// mine")
    assert_equal site_copy, SiteJavascript.path("search.js")
  end

  test "path is basename-only (blocks traversal)" do
    assert_equal "search.js", File.basename(SiteJavascript.path("../../secret/search.js"))
  end

  test "seed copies shipped files once and never touches an existing copy" do
    SiteJavascript.seed!
    %w[search.js gallery.js checkout.js footnotes.js].each do |f|
      assert File.exist?(File.join(SITE, f)), "#{f} seeded"
    end

    File.write(File.join(SITE, "search.js"), "// mine")
    SiteJavascript.seed!
    assert_equal "// mine", File.read(File.join(SITE, "search.js")), "re-seed leaves the site's copy alone"
  end

  test "a freshly seeded copy is current and untouched" do
    SiteJavascript.seed!
    r = SiteJavascript.reports["search.js"]
    assert_equal :tracked_current, r.status
    assert_equal false, r.edited
  end

  test "reports see an edit and an older version" do
    SiteJavascript.seed!
    path = File.join(SITE, "search.js")
    File.write(path, File.read(path).sub(/Version: [\d.]+/, "Version: 0.0.1") + "\n// my tweak\n")

    r = SiteJavascript.reports["search.js"]
    assert_equal :tracked_outdated, r.status
    assert_equal true, r.edited
    assert_not r.safe_to_update?
  end

  test "update! replaces the site copy with the shipped one, and refuses unknown files" do
    FileUtils.mkdir_p(SITE)
    File.write(File.join(SITE, "search.js"), "// old")
    SiteJavascript.update!("search.js")
    assert_equal File.read(File.join(SiteJavascript.source_dir, "search.js")), File.read(File.join(SITE, "search.js"))

    assert_raises(ArgumentError) { SiteJavascript.update!("evil.js") }
  end

  # ── nightly.4 undo ───────────────────────────────────────────────────

  test "a nightly.4 layout is put back: renamed files restored, roe/ removed" do
    roe = File.join(SITE, "roe")
    FileUtils.mkdir_p(roe)
    File.write(File.join(roe, "search.js"), "// roe copy")
    File.write(File.join(SITE, "search.js.2026-09-19"), "// the site's original")
    File.write(File.join(SITE, "custom.js"), "// untouched site file")

    SiteJavascript.seed!

    assert_not File.directory?(roe), "roe/ removed"
    assert_equal "// the site's original", File.read(File.join(SITE, "search.js")), "renamed file restored"
    assert_not File.exist?(File.join(SITE, "search.js.2026-09-19"))
    assert_equal "// untouched site file", File.read(File.join(SITE, "custom.js"))
    assert File.exist?(File.join(SITE, "gallery.js")), "files with no renamed original are seeded fresh"
  end

  test "a renamed file is left in place when its original already exists" do
    roe = File.join(SITE, "roe")
    FileUtils.mkdir_p(roe)
    File.write(File.join(SITE, "search.js"), "// new override")
    File.write(File.join(SITE, "search.js.2026-09-19"), "// old")

    SiteJavascript.seed!

    assert_equal "// new override", File.read(File.join(SITE, "search.js"))
    assert File.exist?(File.join(SITE, "search.js.2026-09-19")), "not clobbered, left for the user"
  end

  test "sites that never had roe/ are untouched by the undo" do
    FileUtils.mkdir_p(SITE)
    File.write(File.join(SITE, "search.js.2026-09-19"), "// unrelated file with the same suffix")
    SiteJavascript.seed!
    assert File.exist?(File.join(SITE, "search.js.2026-09-19")), "no roe/ folder, so nothing is renamed back"
  end
end
