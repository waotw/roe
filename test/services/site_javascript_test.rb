require "test_helper"

# Roe's front-end JS lives in site/javascript/roe/ (Roe's folder, rewritten
# on boot) and a site overrides a file by putting its own copy one level up.
# Resolution: site → roe → shipped source.
class SiteJavascriptTest < ActiveSupport::TestCase
  SITE = SiteJavascript.site_dir
  ROE  = SiteJavascript.roe_dir

  setup do
    # Snapshot the site javascript tree so the test can mutate it freely.
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

  test "path resolves site override, then roe copy, then shipped source" do
    assert_equal File.join(SiteJavascript.source_dir, "search.js"), SiteJavascript.path("search.js")

    FileUtils.mkdir_p(ROE)
    roe_copy = File.join(ROE, "search.js")
    File.write(roe_copy, "// roe")
    assert_equal roe_copy, SiteJavascript.path("search.js"), "roe copy beats shipped source"

    site_copy = File.join(SITE, "search.js")
    File.write(site_copy, "// override")
    assert_equal site_copy, SiteJavascript.path("search.js"), "site override beats roe copy"
    assert SiteJavascript.overridden?("search.js")
  end

  test "path is basename-only (blocks traversal)" do
    assert_equal "search.js", File.basename(SiteJavascript.path("../../secret/search.js"))
  end

  test "seed writes shipped files into roe/ and rewrites them on every boot" do
    SiteJavascript.seed!
    %w[search.js gallery.js checkout.js].each do |f|
      assert File.exist?(File.join(ROE, f)), "#{f} seeded into site/javascript/roe"
      assert_not File.exist?(File.join(SITE, f)), "#{f} not placed directly in site/javascript"
    end

    File.write(File.join(ROE, "search.js"), "// stale")
    SiteJavascript.seed!
    assert_equal File.read(File.join(SiteJavascript.source_dir, "search.js")),
                 File.read(File.join(ROE, "search.js")), "roe/ is Roe's — a re-seed brings it back in step"
  end

  test "seed never touches a site override" do
    FileUtils.mkdir_p(SITE)
    File.write(File.join(SITE, "mine.js"), "// site-only file")
    SiteJavascript.seed!
    File.write(File.join(SITE, "search.js"), "// override")
    SiteJavascript.seed!

    assert_equal "// override", File.read(File.join(SITE, "search.js"))
    assert_equal "// site-only file", File.read(File.join(SITE, "mine.js"))
  end

  # A site from before roe/ existed has Roe's files directly in
  # site/javascript/, where they'd now read as overrides and pin the site to
  # old code. First boot moves them aside — renamed, never deleted.
  test "seed retires pre-roe copies by renaming them with a date" do
    FileUtils.mkdir_p(SITE)
    File.write(File.join(SITE, "search.js"), "// old seeded copy")
    File.write(File.join(SITE, "custom.js"), "// the site's own file")

    SiteJavascript.seed!

    assert_not File.exist?(File.join(SITE, "search.js")), "old copy moved out of the override slot"
    retired = File.join(SITE, "search.js.#{SiteJavascript::RETIRED_SUFFIX_DATE}")
    assert File.exist?(retired), "renamed, not deleted"
    assert_equal "// old seeded copy", File.read(retired)
    assert File.exist?(File.join(SITE, "custom.js")), "a file Roe doesn't ship is left alone"
    assert_equal File.join(ROE, "search.js"), SiteJavascript.path("search.js"), "roe copy now serves"
  end

  test "retiring happens once: an override written after roe/ exists stays put" do
    FileUtils.mkdir_p(SITE)
    File.write(File.join(SITE, "search.js"), "// old seeded copy")
    SiteJavascript.seed!
    assert_equal 1, Dir.glob(File.join(SITE, "search.js.*")).size

    File.write(File.join(SITE, "search.js"), "// my override")
    SiteJavascript.seed!

    assert_equal "// my override", File.read(File.join(SITE, "search.js")), "override left alone on later boots"
    assert_equal 1, Dir.glob(File.join(SITE, "search.js.*")).size, "nothing else retired"
  end
end
