require "test_helper"

class SiteJavascriptTest < ActiveSupport::TestCase
  SITE = SiteJavascript.site_dir

  setup do
    # Snapshot the site javascript dir so the test can mutate it freely.
    @backup = {}
    Dir.glob(File.join(SITE, "*.js")).each { |f| @backup[f] = File.read(f) } if File.directory?(SITE)
  end

  teardown do
    FileUtils.rm_rf(SITE)
    unless @backup.empty?
      FileUtils.mkdir_p(SITE)
      @backup.each { |f, c| File.write(f, c) }
    end
  end

  test "path prefers the site copy, falls back to the shipped source" do
    FileUtils.rm_rf(SITE)
    assert_equal File.join(SiteJavascript.source_dir, "search.js"), SiteJavascript.path("search.js")

    FileUtils.mkdir_p(SITE)
    site_copy = File.join(SITE, "search.js")
    File.write(site_copy, "// override")
    assert_equal site_copy, SiteJavascript.path("search.js"), "site copy wins"
  end

  test "path is basename-only (blocks traversal)" do
    assert_equal "search.js", File.basename(SiteJavascript.path("../../secret/search.js"))
  end

  test "seed copies shipped files and never clobbers an existing site copy" do
    FileUtils.rm_rf(SITE)
    SiteJavascript.seed!

    %w[search.js gallery.js checkout.js].each do |f|
      assert File.exist?(File.join(SITE, f)), "#{f} seeded into site/javascript"
    end

    File.write(File.join(SITE, "search.js"), "// mine")
    SiteJavascript.seed!
    assert_equal "// mine", File.read(File.join(SITE, "search.js")), "re-seed keeps the site override"
  end
end
