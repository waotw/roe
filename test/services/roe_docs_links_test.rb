require "test_helper"

# The links check for Roe's own docs, read from the files (no database), as
# bin/release and `roe links` run it.
class RoeDocsLinksTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir("roe-docs")
    FileUtils.mkdir_p(File.join(@dir, "media", "images"))
    File.write(File.join(@dir, "media", "images", "here.png"), "x")
  end

  teardown { FileUtils.rm_rf(@dir) }

  def doc(file, front, body)
    path = File.join(@dir, file)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "---\n#{front}---\n\n#{body}")
  end

  test "reports broken links, missing media and names, with the file's own line numbers" do
    doc("roeanji_cards.md", "title: Cards\nurl_name: cards\n", "Cards.\n")
    doc("050_glossary.md", "title: Glossary\n", "Words.\n")
    doc("tutorials/01-start.md", "title: 0) Start Here\nrelated:\n  - cards\n  - nowhere\n", <<~MD)
      [Cards](/documentation/roe/cards) and [the glossary](/documentation/roe/glossary#yaml).
      [Old](cards.md) and [gone](/documentation/roe/gone).
      ![here](/media/images/here.png) ![lost](/media/images/lost.png)
      [Admin](/admin) is the site's, not checked.
    MD

    check = RoeDocsLinks.new(@dir).call
    found = check.problems.map { |p| [ p[:where], p[:type] ] }

    assert_equal [
      [ "tutorials/01-start.md:9", :broken_internal_link ],
      [ "tutorials/01-start.md:9", :broken_internal_link ],
      [ "tutorials/01-start.md:10", :missing_media ],
      [ "tutorials/01-start.md (related:)", :broken_internal_link ]
    ], found
    assert check.broken?
    assert_includes check.report_lines, "BROKEN LINKS (3)"
    assert_includes check.report_lines, "MISSING MEDIA (1)"
  end

  test "clean docs pass" do
    doc("a.md", "title: A\n", "[B](/documentation/roe/b)\n")
    doc("b.md", "title: B\n", "[A](/documentation/roe/a)\n")

    refute RoeDocsLinks.new(@dir).call.broken?
  end

  test "bin/roe-docs-links exits 1 when something is broken, 0 when not" do
    doc("a.md", "title: A\n", "[gone](/documentation/roe/gone)\n")
    out, status = Open3.capture2e(Rails.root.join("bin/roe-docs-links").to_s, @dir)
    assert_equal 1, status.exitstatus
    assert_includes out, "a.md:5"

    doc("a.md", "title: A\n", "Nothing to break.\n")
    _out, status = Open3.capture2e(Rails.root.join("bin/roe-docs-links").to_s, @dir)
    assert_equal 0, status.exitstatus
  end
end
