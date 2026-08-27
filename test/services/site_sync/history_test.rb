# frozen_string_literal: true

require "test_helper"

# The transfer job already computed every path it moved and then wrote it to a
# cache key that expired, so after a sync there was no way to answer "what did
# that just do?" — least of all after the sync that removed 9 episodes and 23
# audio files.
class SiteSync::HistoryTest < ActiveSupport::TestCase
  # The log is a real file shared across test files, so start and finish clean
  # rather than trusting whatever ran before.
  def clear! = (File.delete(SiteSync::History.path) if File.exist?(SiteSync::History.path))
  setup    { clear! }
  teardown { clear! }

  test "nothing recorded means no history to link to" do
    assert_not SiteSync::History.exist?
    assert_empty SiteSync::History.recent
  end

  test "an event records both directions separately" do
    SiteSync::History.record!(
      kind: :sync, outcome: :completed,
      to_live:  { added: [ "posts/new.md" ], deleted: [] },
      to_local: { added: [ "pages/about.md" ], deleted: [ "posts/gone.md" ] }
    )

    event = SiteSync::History.recent.sole

    assert_equal "sync", event.kind
    assert_equal [ "posts/new.md" ], event.to_live.changed
    assert_equal [ "pages/about.md" ], event.to_local.changed
    assert_equal [ "posts/gone.md" ], event.to_local.deleted
    assert_empty event.to_live.deleted
  end

  # added and modified are one idea to a reader — the file changed.
  test "added and modified are reported together as changed" do
    SiteSync::History.record!(kind: :push, outcome: :completed,
      to_live: { added: [ "b.md" ], modified: [ "a.md" ], deleted: [] })

    assert_equal %w[a.md b.md], SiteSync::History.recent.sole.to_live.changed
  end

  test "newest first" do
    SiteSync::History.record!(kind: :push, outcome: :completed, at: 2.days.ago)
    SiteSync::History.record!(kind: :pull, outcome: :completed, at: 1.hour.ago)

    assert_equal %w[pull push], SiteSync::History.recent.map(&:kind)
  end

  # The link that makes a deletion recoverable rather than just reported.
  test "the snapshot taken before the sync is recorded" do
    SiteSync::History.record!(kind: :sync, outcome: :completed,
      to_local: { deleted: [ "posts/gone.md" ] },
      snapshot: "/roe/backups/local/2026-08-26-122011")

    assert_equal "2026-08-26-122011", SiteSync::History.recent.sole.snapshot_name
  end

  test "a blocked sync is recorded as having moved nothing" do
    SiteSync::History.record!(kind: :sync, outcome: :blocked, error: "9 unresolved conflict(s)")
    event = SiteSync::History.recent.sole

    assert_equal "blocked", event.outcome
    assert_not event.any_changes?
    assert_match "9 unresolved", event.error
  end

  # A half-written final line shouldn't cost the whole history.
  test "a torn line is skipped, not fatal" do
    SiteSync::History.record!(kind: :push, outcome: :completed, to_live: { added: [ "a.md" ] })
    File.open(SiteSync::History.path, "a") { |f| f.write('{"at":"2026') }

    assert_equal 1, SiteSync::History.recent.size
  end

  test "recording never raises into a sync that worked" do
    SiteSync::History.stubs(:path).returns("/nonexistent-dir-#{SecureRandom.hex(4)}/x/y.jsonl")

    assert_nothing_raised { SiteSync::History.record!(kind: :sync, outcome: :completed) }
  end

  # It lives under backups/, not /site — a log inside /site would sync itself
  # and register as drift on every sync.
  test "the log is outside the synced tree" do
    assert_not SiteSync::History.path.start_with?(RoeSitePaths::SITE_PATH.to_s),
      "the history would sync itself and cause drift"
    assert SiteSync::History.path.start_with?(SiteSync::BackupPaths.root)
  end

  test "the log is trimmed so it can't grow without bound" do
    (SiteSync::History::KEEP + 10).times { |i| SiteSync::History.record!(kind: :push, outcome: :completed, at: i.minutes.ago) }

    assert_equal SiteSync::History::KEEP, File.readlines(SiteSync::History.path).size
  end
end
