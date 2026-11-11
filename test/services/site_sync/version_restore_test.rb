# frozen_string_literal: true

require "test_helper"

# Putting files back from the version store: one change, or the whole site as
# it was just after a sync. Restores write into local /site and are recorded
# themselves, so they can be undone the same way.
class SiteSync::VersionRestoreTest < ActiveSupport::TestCase
  DIR = "zz-version-restore-test"

  setup do
    FileUtils.rm_rf(SiteSync::Versions.root)
    FileUtils.mkdir_p(site(DIR))
    ContentSync.stubs(:sync_all)
  end

  teardown do
    FileUtils.rm_rf(SiteSync::Versions.root)
    FileUtils.rm_rf(site(DIR))
  end

  def site(rel) = File.join(RoeSitePaths::SITE_PATH, rel)
  def read(rel) = File.read(site(rel))

  # A pull replacing rel's contents (nil = deleting it), recorded as one sync.
  def pull(rel, text, kind: :sync)
    recorder = SiteSync::Versions::Recorder.new
    recorder.save_local!([ rel ], deleted: text.nil? ? [ rel ] : [])
    text.nil? ? File.delete(site(rel)) : File.write(site(rel), text)
    recorder.finish!(kind: kind, outcome: :completed)
  end

  test "undoing a change puts the replaced version back, with a new modified time" do
    rel = "#{DIR}/post.md"
    File.write(site(rel), "mine")
    File.utime(Time.at(1_000_000), Time.at(1_000_000), site(rel))
    pull(rel, "live's")

    change = SiteSync::Versions.history_of(rel).first
    result = SiteSync::VersionRestore.changes([ change[:id] ])

    assert_equal [ rel ], result.restored
    assert_equal "mine", read(rel)
    assert_operator File.mtime(site(rel)), :>, 1.minute.ago, "a new mtime, so the next sync pushes it"
  end

  test "a restore is recorded, so it can be undone too" do
    rel = "#{DIR}/post.md"
    File.write(site(rel), "mine")
    pull(rel, "live's")
    SiteSync::VersionRestore.changes([ SiteSync::Versions.history_of(rel).first[:id] ])

    undo = SiteSync::Versions.history_of(rel).first
    assert_equal "restore", SiteSync::Versions.events(limit: 1).first[:kind]
    SiteSync::VersionRestore.changes([ undo[:id] ])
    assert_equal "live's", read(rel)
  end

  test "a deleted file comes back" do
    rel = "#{DIR}/gone.md"
    File.write(site(rel), "keep me")
    pull(rel, nil)

    SiteSync::VersionRestore.changes([ SiteSync::Versions.history_of(rel).first[:id] ])
    assert_equal "keep me", read(rel)
  end

  test "undoing an addition removes the file, keeping it first" do
    rel = "#{DIR}/new.md"
    recorder = SiteSync::Versions::Recorder.new
    recorder.save_local!([ rel ])
    File.write(site(rel), "arrived")
    recorder.finish!(kind: :sync, outcome: :completed)

    result = SiteSync::VersionRestore.changes([ SiteSync::Versions.history_of(rel).first[:id] ])
    assert_equal [ rel ], result.removed
    refute File.exist?(site(rel))
    kept = SiteSync::Versions.history_of(rel).first
    assert_equal "arrived", File.read(SiteSync::Versions.object_path(kept[:before_sha]))
  end

  test "the whole site goes back to just after a sync, and the preview lists only what differs" do
    a = "#{DIR}/a.md"
    b = "#{DIR}/b.md"
    File.write(site(a), "a1")
    File.write(site(b), "b1")
    first = pull(a, "a2")
    pull(a, "a3")
    pull(b, "b2")

    plan = SiteSync::VersionRestore.plan_for_point(first)
    assert_equal [ a, b ].sort, plan.keys.sort

    SiteSync::VersionRestore.point(first)
    assert_equal "a2", read(a)
    assert_equal "b1", read(b)
    assert_empty SiteSync::VersionRestore.plan_for_point(first), "nothing left to change"
  end

  test "never writes outside /site or into paths Site Sync keeps out" do
    secret = "system/secrets/master.key"
    restore = SiteSync::VersionRestore.new(secret => nil, "../outside.md" => nil, "/etc/hosts" => nil)
    result = restore.call
    assert_equal [ "../outside.md", "/etc/hosts", secret ].sort, result.skipped
    assert_empty result.restored + result.removed
  end

  # Only a file's latest change can be undone; once restored, the restore's
  # own entry is where to undo it.
  test "a restored file can only be undone from the restore" do
    rel = "#{DIR}/post.md"
    File.write(site(rel), "mine")
    pull(rel, "live's")
    sync_change = SiteSync::Versions.history_of(rel).first
    SiteSync::VersionRestore.changes([ sync_change[:id] ])
    restore_change = SiteSync::Versions.history_of(rel).first

    states = SiteSync::VersionRestore.row_states(SiteSync::Versions.events)
    assert_equal :restored, states[sync_change[:id]]
    assert_equal :undo, states[restore_change[:id]]

    error = assert_raises(SiteSync::VersionRestore::Error) { SiteSync::VersionRestore.changes([ sync_change[:id] ]) }
    assert_match "changed since", error.message
    assert_equal "mine", read(rel), "the old row didn't write anything"
  end

  test "a change a later sync replaced can't be undone from the earlier one" do
    rel = "#{DIR}/post.md"
    File.write(site(rel), "one")
    first = pull(rel, "two")
    pull(rel, "three")
    states = SiteSync::VersionRestore.row_states(SiteSync::Versions.events)
    first_change = SiteSync::Versions.events.find { |e| e[:id] == first }[:changes].first
    assert_equal :changed, states[first_change[:id]]
  end

  test "a restore point is offered only when it would change something" do
    rel = "#{DIR}/post.md"
    File.write(site(rel), "one")
    first = pull(rel, "two")
    second = pull(rel, "three")

    assert SiteSync::VersionRestore.point_restorable?(first)
    refute SiteSync::VersionRestore.point_restorable?(second), "the site already is how it was after it"
  end
end
