# frozen_string_literal: true

require "test_helper"

# The same collection came out in two different orders on local and live.
#
# Two causes, compounding. Post#date returns a Date, so posts on the same day
# had identical sort keys — the times in their metadata were being discarded.
# And Ruby's sort_by is not stable, so equal keys fell out in whatever order
# the database returned, which differs between a site built up over months and
# one rebuilt in a single sync.
class CollectionDateOrderTest < ActiveSupport::TestCase
  def post(slug, date, time: nil)
    meta = { "title" => slug, "url_name" => slug, "status" => "published", "date" => date }
    meta["time"] = time if time
    Post.create!(file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "#{slug}.md"),
                 content: "Body.", metadata: meta)
  end

  def order(items, by = "date") = CollectionQuery.order_items(items, by).map(&:url_name)

  # ── Post#timestamp ───────────────────────────────────────────────────────

  test "a date alone is midnight" do
    assert_equal Time.zone.parse("2026-08-27 00:00"), post("d1", "2026-08-27").timestamp
  end

  # What a browser date picker writes.
  test "a date carrying a time is that instant" do
    assert_equal Time.zone.parse("2026-08-14T13:45Z"), post("d2", "2026-08-14T13:45Z").timestamp
  end

  test "a separate time field is combined with the date" do
    assert_equal Time.zone.parse("2026-08-27 13:45"), post("d3", "2026-08-27", time: "13:45").timestamp
  end

  # Writing it as its own field is the more deliberate statement.
  test "an explicit time wins over one inside the date" do
    assert_equal Time.zone.parse("2026-08-27 17:30"),
                 post("d4", "2026-08-27T09:00", time: "17:30").timestamp
  end

  test "an unparseable time falls back to the date rather than raising" do
    assert_equal Time.zone.parse("2026-08-27 00:00"),
                 post("d5", "2026-08-27", time: "lunchtime").timestamp
  end

  test "no date at all is nil" do
    assert_nil Post.new(metadata: {}).timestamp
  end

  # ── Ordering ─────────────────────────────────────────────────────────────

  test "posts on the same day order by their times" do
    late  = post("late",  "2026-06-05T16:49Z")
    early = post("early", "2026-06-05T16:42Z")
    mid   = post("mid",   "2026-06-05T16:47Z")

    assert_equal %w[late mid early], order([ early, mid, late ])
    assert_equal %w[early mid late], order([ late, mid, early ], "date-asc")
  end

  # The heart of it: the answer must not depend on the order they arrived in.
  test "the order doesn't depend on the input order" do
    items = [ post("a", "2026-06-05T10:00Z"), post("b", "2026-06-05T10:00Z"),
              post("c", "2026-06-05T10:00Z"), post("d", "2026-06-05T09:00Z") ]

    orders = 10.times.map { order(items.shuffle) }.uniq

    assert_equal 1, orders.size, "the same posts sorted #{orders.size} different ways"
  end

  # url_name because it comes from the content — a database id or row order
  # would put two environments straight back where they started.
  test "identical timestamps tie-break on url_name, ascending either way" do
    items = [ post("zulu", "2026-06-05T10:00Z"), post("alpha", "2026-06-05T10:00Z") ]

    assert_equal %w[alpha zulu], order(items)
    assert_equal %w[alpha zulu], order(items, "date-asc")
  end

  test "undated posts sort to the end in both directions" do
    dated = post("dated", "2026-06-05")
    undated = Post.create!(file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "undated.md"),
      content: "x", metadata: { "title" => "u", "url_name" => "undated", "status" => "published" })

    assert_equal %w[dated undated], order([ undated, dated ])
    assert_equal %w[dated undated], order([ undated, dated ], "date-asc")
  end

  # A second implementation of the same four keywords lived in StaticGenerator,
  # in SQL against the raw date string — no tie-break, and blind to `time:`.
  test "the static generator orders identically" do
    items = [ post("s1", "2026-06-05T16:49Z"), post("s2", "2026-06-05T16:42Z"),
              post("s3", "2026-06-05T16:42Z") ]

    assert_equal order(items),
                 StaticGenerator.new.send(:apply_collection_order, items, "date").map(&:url_name)
  end
end
