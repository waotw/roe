# frozen_string_literal: true

require "test_helper"

# Rewinding the newest sync: each side goes back to how it was just before
# it, and so does the record of what both sides agreed on, so the next sync
# would make the same changes again.
class SiteSync::RewindTest < ActiveSupport::TestCase
  DIR = "zz-rewind-test"
  OLD = Time.at(1_700_000_000)
  NEW = Time.at(1_700_100_000)

  setup do
    FileUtils.rm_rf(SiteSync::Versions.root)
    FileUtils.mkdir_p(site(DIR))
    ContentSync.stubs(:sync_all)
    SiteSync::Exchange.stubs(:reconcile_peer_content!)
    SiteSync::Exchange.stubs(:refresh_peer_ledger!)
    SiteSync::Exchange.stubs(:can_call_peer?).returns(false)
    @scratch = Dir.mktmpdir("rewind-test")
    @post = "#{DIR}/post.md"
    @css  = "#{DIR}/theme.css"
  end

  teardown do
    FileUtils.rm_rf(SiteSync::Versions.root)
    FileUtils.rm_rf(site(DIR))
    FileUtils.rm_rf(@scratch)
  end

  def site(rel) = File.join(RoeSitePaths::SITE_PATH, rel)

  def write(rel, text, time, root: RoeSitePaths::SITE_PATH)
    abs = File.join(root, rel)
    FileUtils.mkdir_p(File.dirname(abs))
    File.write(abs, text)
    File.utime(time, time, abs)
  end

  def entry(text, time) = { "size" => text.bytesize, "mtime" => time.to_i }

  # A sync that pulled a live edit to post.md and pushed a local edit to
  # theme.css. Returns the event.
  def sync!
    write(@post, "post before", OLD)
    write(@css, "css after", NEW)
    live_backup = File.join(@scratch, "live-before")
    write(@css, "css before", OLD, root: live_backup)

    recorder = SiteSync::Versions::Recorder.new
    recorder.save_live!([ @css ], from: live_backup, peer: { @css => entry("css before", OLD) })
    recorder.save_local!([ @post ])
    write(@post, "post after", NEW)
    SiteSync::Versions.event(recorder.finish!(kind: :sync, outcome: :completed))
  end

  # Live as the sync left it.
  def live_after
    { @css => entry("css after", NEW), @post => entry("post after", NEW) }
  end

  test "each side goes back to before the sync, and so does the agreed record" do
    event = sync!
    SiteSync::Exchange.stubs(:fetch_peer_manifest).returns({ "files" => live_after })
    SiteSync::Ledger.stubs(:recorded).returns({ "files" => live_after })

    live_now = File.join(@scratch, "live-now")
    write(@css, "css after", NEW, root: live_now)
    transport = mock("transport")
    transport.stubs(:backup_live_to_local!).returns(live_now)
    pushed = nil
    transport.expects(:push_local_to_live!).with do |diff:, root:, **|
      pushed = { diff: diff, text: File.read(File.join(root, @css)), mtime: File.mtime(File.join(root, @css)) }
    end
    SiteSync.stubs(:transport).returns(transport)
    baseline = nil
    SiteSync::Ledger.expects(:write_manifest!).with { |files| baseline = files }
    # Live's own record goes back to the same entries, so its report agrees.
    SiteSync::Exchange.expects(:rewind_peer_ledger!)
                      .with({ @css => entry("css before", OLD), @post => entry("post before", OLD) })

    SiteSync::Rewind.perform!(event)

    assert_equal [ @css ], pushed[:diff][:added]
    assert_equal "css before", pushed[:text]
    assert_equal OLD, pushed[:mtime], "live gets the time it had, so it reads as untouched"
    assert_equal "post before", File.read(site(@post))
    assert_equal OLD, File.mtime(site(@post))
    assert_equal "css after", File.read(site(@css)), "local keeps what it sent"
    assert_equal entry("css before", OLD), baseline[@css]
    assert_equal entry("post before", OLD), baseline[@post]

    events = SiteSync::Versions.events
    assert_equal "rewind", events.first[:kind]
    assert_equal event[:id], events.first[:undoes]
    assert_equal events.first[:id], events.find { |e| e[:id] == event[:id] }[:rewound_by]
    assert_nil SiteSync::Rewind.candidate, "nothing older to rewind"
  end

  test "the next sync makes the same changes again" do
    event = sync!
    SiteSync::Exchange.stubs(:fetch_peer_manifest).returns({ "files" => live_after })
    SiteSync::Ledger.stubs(:recorded).returns({ "files" => live_after })
    transport = stub(backup_live_to_local!: (File.join(@scratch, "live-now").tap { |d| write(@css, "css after", NEW, root: d) }))
    transport.stubs(:push_local_to_live!)
    SiteSync.stubs(:transport).returns(transport)
    baseline = nil
    SiteSync::Ledger.stubs(:write_manifest!).with { |files| baseline = files }

    SiteSync::Rewind.perform!(event)

    live_rewound = live_after.merge(@css => entry("css before", OLD))
    local = { @css => entry("css after", NEW), @post => entry("post before", OLD) }
    result = SiteSync::Reconciler.reconcile(baseline: baseline, local: local, peer: live_rewound)
    assert_equal [ @css ], result.push
    assert_equal [ @post ], result.pull
    assert_empty result.conflicts
  end

  test "a file the sync added is removed again" do
    recorder = SiteSync::Versions::Recorder.new
    recorder.save_local!([ @post ])
    write(@post, "new from live", NEW)
    event = SiteSync::Versions.event(recorder.finish!(kind: :sync, outcome: :completed))
    SiteSync::Exchange.stubs(:fetch_peer_manifest).returns({ "files" => { @post => entry("new from live", NEW) } })
    SiteSync::Ledger.stubs(:recorded).returns({ "files" => { @post => entry("new from live", NEW) } })
    baseline = nil
    SiteSync::Ledger.stubs(:write_manifest!).with { |files| baseline = files }

    SiteSync::Rewind.perform!(event)

    refute File.exist?(site(@post))
    refute baseline.key?(@post)
  end

  test "files changed since the sync are named before anything happens" do
    event = sync!
    write(@post, "edited since", NEW + 60)
    plan = SiteSync::Rewind.plan(event, peer: live_after.merge(@css => entry("edited on live", NEW + 60)))

    assert_equal [ @css, @post ].sort, plan.changed_since.map(&:path).sort
  end

  test "only the newest sync can be rewound" do
    first = sync!
    recorder = SiteSync::Versions::Recorder.new
    recorder.save_local!([ @post ])
    write(@post, "again", NEW + 60)
    second = recorder.finish!(kind: :sync, outcome: :completed)

    assert_equal second, SiteSync::Rewind.candidate[:id]
    assert_raises(SiteSync::Rewind::Error) { SiteSync::Rewind.perform!(first) }
  end

  test "nothing changes when live can't be reached" do
    event = sync!
    SiteSync::Exchange.stubs(:fetch_peer_manifest).returns(nil)
    SiteSync.expects(:transport).never

    assert_raises(SiteSync::Rewind::Unreachable) { SiteSync::Rewind.perform!(event) }
    assert_equal "post after", File.read(site(@post))
  end

  test "an older history file gains the new columns and still reads" do
    FileUtils.mkdir_p(SiteSync::Versions.root)
    db = SQLite3::Database.new(SiteSync::Versions.db_path)
    db.execute_batch(<<~SQL)
      CREATE TABLE events (id INTEGER PRIMARY KEY, at TEXT NOT NULL, kind TEXT NOT NULL, outcome TEXT NOT NULL);
      CREATE TABLE changes (id INTEGER PRIMARY KEY, event_id INTEGER NOT NULL, path TEXT NOT NULL, direction TEXT NOT NULL,
        action TEXT NOT NULL, before_sha TEXT, before_size INTEGER, after_sha TEXT, after_size INTEGER);
      INSERT INTO events VALUES (1, '2026-11-11T19:36:00.000Z', 'sync', 'completed');
      INSERT INTO changes VALUES (1, 1, 'posts/a.md', 'to_local', 'added', NULL, NULL, NULL, 3);
      PRAGMA user_version = 1;
    SQL
    db.close

    event = SiteSync::Versions.events.first
    assert_nil event[:rewound_by]
    assert_nil event[:changes].first[:before_mtime]
    assert_equal 1, SiteSync::Rewind.candidate[:id]
  end
end
