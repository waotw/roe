require "test_helper"

# One inspector for every file Roe seeds into site/ and the site then owns:
# themes and front-end scripts. The header's Version says which shipped file
# the copy started as; the Fingerprint says whether its body was changed
# since. Nothing here writes to site/ except through stamp!, which is only
# ever run on the shipped copies at release time.
class ShippedFileInspectorTest < ActiveSupport::TestCase
  setup { @dir = Dir.mktmpdir("shipped") }
  teardown { FileUtils.rm_rf(@dir) }

  def write(name, content)
    path = File.join(@dir, name)
    File.write(path, content)
    path
  end

  def script(version:, body: "console.log('hi');\n", fingerprint: :auto, name: "search")
    header = <<~JS
      /* ============= ROE SCRIPT ================
         Roe Script: #{name}
         Version: #{version}
         FP_LINE
         ========================================= */
    JS
    fp = fingerprint == :auto ? ShippedFileInspector.fingerprint_of(header.sub("FP_LINE\n", "") + body) : fingerprint
    header = fp ? header.sub("FP_LINE", "Fingerprint: #{fp}") : header.sub("   FP_LINE\n", "")
    header + body
  end

  # ── Header parsing ───────────────────────────────────────────────────

  test "parses a script header, including the fingerprint" do
    path = write("search.js", script(version: "1.2.0"))
    h = ShippedFileInspector.parse_header(path, kind: :script)

    assert_equal "search", h.name
    assert_equal "1.2.0", h.version
    assert_match(/\A[0-9a-f]{8}\z/, h.fingerprint)
  end

  test "parses a theme header through the theme label" do
    path = write("default.css", "/* THEME INFO\n   Roe Theme: Default\n   Version: 0.1.0\n */\nbody{}")
    assert_equal "Default", ShippedFileInspector.parse_header(path, kind: :theme).name
    assert_nil ShippedFileInspector.parse_header(path, kind: :script), "a theme header is not a script header"
  end

  test "a file with no header parses as nil" do
    assert_nil ShippedFileInspector.parse_header(write("x.js", "console.log(1)"), kind: :script)
  end

  # ── Fingerprint ──────────────────────────────────────────────────────

  test "fingerprint covers the body only, so the header's own lines don't change it" do
    a = write("a.js", script(version: "1.0.0"))
    b = write("b.js", script(version: "9.9.9"))
    assert_equal ShippedFileInspector.fingerprint(a), ShippedFileInspector.fingerprint(b)
  end

  test "editing the body changes the fingerprint" do
    a = write("a.js", script(version: "1.0.0"))
    b = write("b.js", script(version: "1.0.0", body: "console.log('changed');\n"))
    assert_not_equal ShippedFileInspector.fingerprint(a), ShippedFileInspector.fingerprint(b)
  end

  # ── edited? ──────────────────────────────────────────────────────────

  test "an untouched install is not edited" do
    assert_not ShippedFileInspector.edited?(write("search.js", script(version: "1.0.0")))
  end

  test "a body edit below an intact header is detected" do
    content = script(version: "1.0.0")
    edited  = content.sub("console.log('hi');", "console.log('mine');")
    assert ShippedFileInspector.edited?(write("search.js", edited))
  end

  test "a header with no fingerprint and an unknown body is treated as edited — the cautious answer" do
    assert ShippedFileInspector.edited?(write("search.js", script(version: "1.0.0", fingerprint: nil)))
  end

  # ── Files from before headers existed ────────────────────────────────

  test "a headerless file whose body Roe once shipped reads as that release, untouched" do
    legacy_fp, entry = ShippedFileInspector::LEGACY.first
    # Fake a body with that fingerprint by stubbing the hash, since the real
    # legacy bodies are release artefacts, not fixtures.
    path = write("search.js", "// the old shipped body\n")
    ShippedFileInspector.stubs(:fingerprint).with(path).returns(legacy_fp)

    h = ShippedFileInspector.parse_header(path, kind: :script)
    assert_equal entry[:name], h.name
    assert_equal entry[:version], h.version
    assert_not ShippedFileInspector.edited?(path)

    r = ShippedFileInspector.report(bundled_path: bundled, installed_path: path)
    assert_equal :tracked_outdated, r.status if entry[:name] == "search"
    assert r.safe_to_update? if entry[:name] == "search"
  end

  test "a headerless file with an unknown body is custom" do
    path = write("search.js", "// something else entirely\n")
    assert_nil ShippedFileInspector.parse_header(path, kind: :script)
    assert_equal :custom, ShippedFileInspector.status(bundled_path: bundled, installed_path: path)
  end

  # ── status and report ────────────────────────────────────────────────

  def bundled(version: "2.0.0", body: "console.log('new');\n")
    write("bundled.js", script(version: version, body: body))
  end

  test "not installed when the site has no copy" do
    r = ShippedFileInspector.report(bundled_path: bundled, installed_path: File.join(@dir, "missing.js"))
    assert_equal :not_installed, r.status
    assert_not r.update_available?
  end

  test "outdated and untouched is safe to update" do
    installed = write("search.js", script(version: "1.0.0"))
    r = ShippedFileInspector.report(bundled_path: bundled, installed_path: installed)

    assert_equal :tracked_outdated, r.status
    assert_equal false, r.edited
    assert r.safe_to_update?
  end

  test "outdated and edited is an update to offer, never to apply" do
    installed = write("search.js", script(version: "1.0.0").sub("'hi'", "'mine'"))
    r = ShippedFileInspector.report(bundled_path: bundled, installed_path: installed)

    assert_equal :tracked_outdated, r.status
    assert_equal true, r.edited
    assert r.update_available?
    assert_not r.safe_to_update?
  end

  test "current when versions match" do
    installed = write("search.js", script(version: "2.0.0"))
    assert_equal :tracked_current, ShippedFileInspector.status(bundled_path: bundled, installed_path: installed)
  end

  test "ahead when the install is newer than shipped" do
    installed = write("search.js", script(version: "3.0.0"))
    assert_equal :tracked_ahead, ShippedFileInspector.status(bundled_path: bundled, installed_path: installed)
  end

  test "custom when the header is gone or the name was changed" do
    assert_equal :custom, ShippedFileInspector.status(bundled_path: bundled, installed_path: write("a.js", "// mine"))
    renamed = write("b.js", script(version: "1.0.0", name: "my-search"))
    assert_equal :custom, ShippedFileInspector.status(bundled_path: bundled, installed_path: renamed)
  end

  test "version comparison pads missing components" do
    assert_equal 0,  ShippedFileInspector.compare_versions("1.0", "1.0.0")
    assert_equal 1,  ShippedFileInspector.compare_versions("1.10.0", "1.9.9")
    assert_equal(-1, ShippedFileInspector.compare_versions("0.9", "1.0"))
  end

  # ── stamp! (release time) ────────────────────────────────────────────

  test "stamp! writes a fingerprint matching the body, and is idempotent" do
    path = write("search.js", script(version: "1.0.0", fingerprint: nil))
    assert_equal :stamped, ShippedFileInspector.stamp!(path)

    h = ShippedFileInspector.parse_header(path, kind: :script)
    assert_equal ShippedFileInspector.fingerprint(path), h.fingerprint
    assert_not ShippedFileInspector.edited?(path)
    assert_equal :unchanged, ShippedFileInspector.stamp!(path)
  end

  test "stamp! replaces a stale fingerprint after a body edit" do
    path = write("search.js", script(version: "1.0.0"))
    File.write(path, File.read(path).sub("'hi'", "'new body'"))
    assert ShippedFileInspector.edited?(path), "stale before stamping"

    assert_equal :stamped, ShippedFileInspector.stamp!(path)
    assert_not ShippedFileInspector.edited?(path)
  end

  test "stamp! refuses a file with no header" do
    assert_equal :no_header, ShippedFileInspector.stamp!(write("x.js", "console.log(1)"))
  end
end
