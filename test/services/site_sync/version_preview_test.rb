# frozen_string_literal: true

require "test_helper"

class SiteSync::VersionPreviewTest < ActiveSupport::TestCase
  def kinds(lines) = lines.map { |l| [ l.kind, l.text ] }

  test "a diff shows removed lines before added ones, with three lines of context" do
    before = (1..10).map { |i| "line #{i}" }.join("\n")
    after  = before.sub("line 5", "line five")
    lines = SiteSync::VersionPreview.diff(before, after)

    assert_equal [ :gap, nil ], [ lines.first.kind, lines.first.text ]
    assert_equal [ [ :removed, "line 5" ], [ :added, "line five" ] ], kinds(lines).select { |k, _| k == :removed || k == :added }
    assert_equal %w[line\ 2 line\ 3 line\ 4], lines[1..3].map(&:text)
    assert_equal 5, lines.find { |l| l.kind == :removed }.old_no
  end

  test "identical text has no diff lines; a new file is all added" do
    assert_empty SiteSync::VersionPreview.diff("a\nb", "a\nb")
    assert_equal [ :added, :added ], SiteSync::VersionPreview.diff("", "a\nb").map(&:kind)
  end

  test "the line operations rebuild both versions" do
    rng = Random.new(42)
    20.times do
      a = Array.new(rng.rand(0..40)) { %w[a b c d e].sample(random: rng) }
      b = a.dup
      rng.rand(0..8).times { b.insert(rng.rand(0..b.size), %w[x a b].sample(random: rng)) }
      rng.rand(0..5).times { b.delete_at(rng.rand(0...b.size)) if b.any? }
      ops = SiteSync::VersionPreview.line_ops(a, b)
      assert_equal a, ops.reject { |k, _| k == :added }.map(&:last)
      assert_equal b, ops.reject { |k, _| k == :removed }.map(&:last)
    end
  end

  test "a small change deep in a long file still diffs" do
    a = (1..20_000).map { |i| "rule #{i}" }
    b = a.dup
    b[3] = "rule four"
    b.insert(15_000, "@media (scripting: enabled) {")
    lines = SiteSync::VersionPreview.diff(a.join("\n"), b.join("\n"))
    assert_equal 3, lines.count { |l| l.kind != :same && l.kind != :gap }
  end

  test "binary contents aren't shown as text" do
    Tempfile.create("bin") do |f|
      f.binmode
      f.write("PNG\0\x01\x02")
      f.flush
      assert_nil SiteSync::VersionPreview.text_of(f.path)
    end
  end
end
