require "test_helper"

# Release notes come from the release on the forge, written in markdown, and
# show on the Updates page. They used to be cut to 600 characters and printed
# with simple_format, so headings, lists and `code` arrived as raw markdown.
class ReleaseNotesTest < ActionView::TestCase
  include AdminHelper

  def summary(name, body) = RoeUpdater::VersionChecker.send(:build_summary, name, body)

  test "notes render as markdown: headings, lists, emphasis, code" do
    html = release_notes_html("## What's new\n\n- **Bold** item\n- `code` item\n\n1. first")

    assert_includes html, "<h2"
    assert_includes html, "<ul>"
    assert_includes html, "<strong>Bold</strong>"
    assert_includes html, "<code>code</code>"
    assert_includes html, "<ol>"
    assert_not_includes html, "**"
    assert_not_includes html, "## "
  end

  test "notes from the network can't put scripts, images or handlers on an admin page" do
    html = release_notes_html("Hi <script>alert(1)</script> <img src=x onerror=alert(1)> [x](javascript:alert(1)) <b onclick=\"x\">b</b>")

    assert_not_includes html, "<script"
    assert_not_includes html, "<img"
    assert_not_includes html, "javascript:"
    assert_not_includes html, "onclick"
    # The <img> survives only as escaped text — `&lt;img … onerror=…&gt;` —
    # which the browser shows and never runs. No real attribute gets through.
    assert_no_match(/<[a-z][^>]*\son\w+=/i, html)
  end

  test "links open in a new tab" do
    html = release_notes_html("[Roe](https://go-roe.com)")
    assert_includes html, %(<a target="_blank" rel="noopener" href="https://go-roe.com">Roe</a>)
  end

  test "the summary keeps the whole body, with Windows line endings normalised" do
    body = "# Roe 1.0\r\n\r\n" + ("- a change\r\n" * 200)
    out = summary("Roe - 1.0", body)

    assert_equal 200, out.scan("- a change").size, "not cut short"
    assert_not_includes out, "\r"
  end

  test "the release name is added only when the body doesn't open with its own heading" do
    assert_equal "# Roe 1.0\n\nNotes", summary("Roe - 1.0", "# Roe 1.0\n\nNotes")
    assert_equal "**Roe - 1.0**\n\nNotes", summary("Roe - 1.0", "Notes")
    assert_equal "No release notes were published for this version.", summary(nil, nil)
  end

  test "release links name the forge they point at" do
    assert_equal "GitHub", forge_name("https://github.com/waotw/roe/releases/tag/v1.0")
    assert_equal "Codeberg", forge_name("https://codeberg.org/waotw/roe/releases/tag/v1.0")
    assert_equal "the release page", forge_name("not a url")
  end
end
