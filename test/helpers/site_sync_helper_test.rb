require "test_helper"

class SiteSyncHelperTest < ActionView::TestCase
  test "collapses documentation/roe files into one row" do
    paths = %w[
      documentation/roe/00-intro.md
      documentation/roe/01-guide.md
      documentation/roe/sub/deep.md
      posts/hello.md
    ]
    rows = collapse_sync_paths(paths)
    assert_equal 2, rows.size
    assert_includes rows, "posts/hello.md"
    assert(rows.any? { |r| r == "Roe documentation — 3 files changed" }, "expected a grouped docs row, got #{rows.inspect}")
  end

  test "the exact prefix path itself collapses" do
    rows = collapse_sync_paths(%w[documentation/roe])
    assert_equal [ "Roe documentation — 1 file changed" ], rows
  end

  test "singular vs plural wording" do
    assert_match(/1 file changed/,  collapse_sync_paths(%w[documentation/roe/a.md]).first)
    assert_match(/2 files changed/, collapse_sync_paths(%w[documentation/roe/a.md documentation/roe/b.md]).first)
  end

  test "ungrouped paths pass through, sorted" do
    assert_equal %w[a.md b.md], collapse_sync_paths(%w[b.md a.md])
  end

  test "a similarly-named sibling prefix is NOT collapsed" do
    rows = collapse_sync_paths(%w[documentation/roego/x.md documentation/roe/y.md])
    assert_equal 2, rows.size
    assert_includes rows, "documentation/roego/x.md"
    assert(rows.any? { |r| r.start_with?("Roe documentation") })
  end

  test "collapsed_sync_count returns the grouped tally" do
    assert_equal 1, collapsed_sync_count(%w[documentation/roe/a.md documentation/roe/b.md])
    assert_equal 2, collapsed_sync_count(%w[documentation/roe/a.md posts/x.md])
    assert_equal 0, collapsed_sync_count([])
    assert_equal 0, collapsed_sync_count(nil)
  end
end
