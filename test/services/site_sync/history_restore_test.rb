# frozen_string_literal: true

require "test_helper"

# Recovering from a bad sync by hand means diffing a snapshot against /site,
# working out which differences the sync caused, copying those back and
# reconciling the database. The history already knows every path involved.
class SiteSync::HistoryRestoreTest < ActiveSupport::TestCase
  SNAPSHOT = "2026-08-26-122011"

  setup do
    @snapshot_dir = File.join(SiteSync::BackupPaths.local, SNAPSHOT)
    FileUtils.mkdir_p(File.join(@snapshot_dir, "posts"))
    File.write(File.join(@snapshot_dir, "posts", "ep.md"), "original body")
    SiteSync::BackupManager.stubs(:create).returns(nil)
    ContentSync.stubs(:sync_all)
  end

  teardown do
    FileUtils.rm_rf(@snapshot_dir)
    FileUtils.rm_f(File.join(RoeSitePaths::SITE_PATH, "posts", "ep.md"))
  end

  def site_file(rel) = File.join(RoeSitePaths::SITE_PATH, rel)

  test "a deleted file comes back" do
    assert_not File.exist?(site_file("posts/ep.md")), "precondition"

    result = SiteSync::HistoryRestore.call(snapshot_name: SNAPSHOT, paths: [ "posts/ep.md" ])

    assert_equal [ "posts/ep.md" ], result.restored
    assert_equal "original body", File.read(site_file("posts/ep.md"))
  end

  test "an overwritten file is put back to its pre-sync version" do
    FileUtils.mkdir_p(File.dirname(site_file("posts/ep.md")))
    File.write(site_file("posts/ep.md"), "what the sync wrote")

    SiteSync::HistoryRestore.call(snapshot_name: SNAPSHOT, paths: [ "posts/ep.md" ])

    assert_equal "original body", File.read(site_file("posts/ep.md"))
  end

  # Restoring overwrites, so it earns the same net a sync gets.
  test "the current state is snapshotted before anything is overwritten" do
    SiteSync::BackupManager.unstub(:create)
    SiteSync::BackupManager.expects(:create).once

    SiteSync::HistoryRestore.call(snapshot_name: SNAPSHOT, paths: [ "posts/ep.md" ])
  end

  # A file on disk that no model row knows about is invisible in the admin.
  test "the database is reconciled afterwards" do
    ContentSync.unstub(:sync_all)
    ContentSync.expects(:sync_all).once

    SiteSync::HistoryRestore.call(snapshot_name: SNAPSHOT, paths: [ "posts/ep.md" ])
  end

  test "nothing to restore means nothing is touched" do
    ContentSync.unstub(:sync_all)
    ContentSync.expects(:sync_all).never

    result = SiteSync::HistoryRestore.call(snapshot_name: SNAPSHOT, paths: [ "posts/not-in-snapshot.md" ])

    assert_empty result.restored
    assert_equal [ "posts/not-in-snapshot.md" ], result.skipped
  end

  # ── Refusals ─────────────────────────────────────────────────────────────

  test "a snapshot that no longer exists is refused" do
    assert_raises(SiteSync::HistoryRestore::Error) do
      SiteSync::HistoryRestore.call(snapshot_name: "2020-01-01-000000", paths: [ "posts/ep.md" ])
    end
  end

  test "an empty selection is refused" do
    assert_raises(SiteSync::HistoryRestore::Error) do
      SiteSync::HistoryRestore.call(snapshot_name: SNAPSHOT, paths: [])
    end
  end

  # The snapshot name comes off a form, so it's matched against the real
  # listing rather than joined onto a path.
  test "a snapshot name can't walk out of the backups directory" do
    [ "../../../etc", "..", "latest/../..", "2026-08-26-122011/../.." ].each do |name|
      assert_raises(SiteSync::HistoryRestore::Error, "#{name.inspect} was accepted") do
        SiteSync::HistoryRestore.call(snapshot_name: name, paths: [ "posts/ep.md" ])
      end
    end
  end

  test "a path can't escape the snapshot" do
    result = SiteSync::HistoryRestore.call(
      snapshot_name: SNAPSHOT,
      paths: [ "../../../../etc/passwd", "../2026-07-23-163512/posts/ep.md" ]
    )

    assert_empty result.restored
  end

  # system/secrets/ holds this install's master key. It must never be written
  # from a snapshot — that's the same rule the tar unpacker enforces.
  test "excluded paths are refused even when present in the snapshot" do
    FileUtils.mkdir_p(File.join(@snapshot_dir, "system", "secrets"))
    File.write(File.join(@snapshot_dir, "system", "secrets", "master.key"), "leaked")

    result = SiteSync::HistoryRestore.call(snapshot_name: SNAPSHOT, paths: [ "system/secrets/master.key" ])

    assert_empty result.restored
    assert_includes result.skipped, "system/secrets/master.key"
    assert_not File.exist?(site_file("system/secrets/master.key"))
  end

  test "a good path is still restored alongside a refused one" do
    result = SiteSync::HistoryRestore.call(
      snapshot_name: SNAPSHOT, paths: [ "posts/ep.md", "../escape.md" ]
    )

    assert_equal [ "posts/ep.md" ], result.restored
    assert_equal [ "../escape.md" ], result.skipped
  end
end
