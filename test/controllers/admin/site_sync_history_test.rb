# frozen_string_literal: true

require "test_helper"

class Admin::SiteSyncHistoryTest < ActionDispatch::IntegrationTest
  def clear! = (File.delete(SiteSync::History.path) if File.exist?(SiteSync::History.path))
  setup { clear!; sign_in_as(User.take) }
  teardown { clear! }

  # A link to an empty page is a dead end on a screen that's already dense.
  test "no link until there's something to read" do
    get admin_site_sync_path

    assert_response :success
    assert_no_match admin_site_sync_history_path, response.body
  end

  test "the link appears once a sync has been recorded" do
    SiteSync::History.record!(kind: :sync, outcome: :completed, to_live: { added: [ "a.md" ] })

    get admin_site_sync_path

    assert_match admin_site_sync_history_path, response.body
  end

  test "the page splits an event by direction" do
    SiteSync::History.record!(
      kind: :sync, outcome: :completed,
      to_live:  { added: [ "posts/pushed.md" ] },
      to_local: { added: [ "posts/pulled.md" ], deleted: [ "posts/removed.md" ] },
      snapshot: "/roe/backups/local/2026-08-26-122011"
    )

    get admin_site_sync_history_path

    assert_response :success
    assert_match "Local → Live", response.body
    assert_match "Live → Local", response.body
    assert_match "posts/pushed.md", response.body
    assert_match "posts/pulled.md", response.body
    assert_match "posts/removed.md", response.body
    assert_match "2026-08-26-122011", response.body,
      "a deletion needs to name where the file can still be found"
  end

  test "an empty history reads as empty rather than erroring" do
    get admin_site_sync_history_path

    assert_response :success
    assert_match "No syncs recorded yet", response.body
  end

  # ── Restore ──────────────────────────────────────────────────────────────

  def with_snapshot(name = "2026-08-26-122011")
    dir = File.join(SiteSync::BackupPaths.local, name)
    FileUtils.mkdir_p(File.join(dir, "posts"))
    File.write(File.join(dir, "posts", "ep.md"), "original body")
    yield name, dir
  ensure
    FileUtils.rm_rf(dir)
    FileUtils.rm_f(File.join(RoeSitePaths::SITE_PATH, "posts", "ep.md"))
  end

  test "only the Live → Local side is selectable" do
    with_snapshot do |name|
      SiteSync::History.record!(kind: :sync, outcome: :completed,
        to_live:  { added: [ "posts/pushed.md" ] },
        to_local: { deleted: [ "posts/ep.md" ] },
        snapshot: File.join(SiteSync::BackupPaths.local, name))

      get admin_site_sync_history_path

      assert_match 'value="posts/ep.md"', response.body, "the local side is restorable"
      assert_no_match 'value="posts/pushed.md"', response.body,
        "a local snapshot can't speak to what happened on live"
      assert_match "RESTORE SELECTED", response.body
    end
  end

  # Snapshots are pruned. Offering a restore that can't work is worse than not
  # offering one.
  test "a pruned snapshot offers no restore and says why" do
    SiteSync::History.record!(kind: :sync, outcome: :completed,
      to_local: { deleted: [ "posts/ep.md" ] },
      snapshot: File.join(SiteSync::BackupPaths.local, "2020-01-01-000000"))

    get admin_site_sync_history_path

    assert_no_match "RESTORE SELECTED", response.body
    # The copy wraps across lines in the template, so match tolerantly rather
    # than pinning the whitespace.
    assert_match(/has\s+since\s+been\s+removed/, response.body)
    assert_match "2020-01-01-000000", response.body
  end

  test "restoring puts the file back and reports it" do
    SiteSync::BackupManager.stubs(:create).returns(nil)
    ContentSync.stubs(:sync_all)

    with_snapshot do |name|
      post admin_restore_from_site_sync_history_path, params: { snapshot: name, paths: [ "posts/ep.md" ] }

      assert_redirected_to admin_site_sync_history_path
      assert_match(/Restored 1 file/, flash[:notice])
      assert_equal "original body", File.read(File.join(RoeSitePaths::SITE_PATH, "posts", "ep.md"))
    end
  end

  test "a bad snapshot name is refused with a message, not an error" do
    post admin_restore_from_site_sync_history_path,
         params: { snapshot: "../../../etc", paths: [ "posts/ep.md" ] }

    assert_redirected_to admin_site_sync_history_path
    assert_match(/no longer exists/, flash[:alert])
  end

  test "selecting nothing is refused" do
    with_snapshot do |name|
      post admin_restore_from_site_sync_history_path, params: { snapshot: name, paths: [] }

      assert_match(/No files selected/, flash[:alert])
    end
  end

  # ── The page remembers what's already back ───────────────────────────────

  test "a file already matching the snapshot is marked, not offered again" do
    with_snapshot do |name|
      # Put the file back exactly as the snapshot has it.
      FileUtils.mkdir_p(File.join(RoeSitePaths::SITE_PATH, "posts"))
      File.write(File.join(RoeSitePaths::SITE_PATH, "posts", "ep.md"), "original body")

      SiteSync::History.record!(kind: :sync, outcome: :completed,
        to_local: { deleted: [ "posts/ep.md" ] },
        snapshot: File.join(SiteSync::BackupPaths.local, name))

      get admin_site_sync_history_path

      assert_match "Restored", response.body
      assert_match "ALL CHANGES RESTORED", response.body
      assert_no_match "RESTORE SELECTED", response.body
      assert_no_match 'value="posts/ep.md"', response.body, "it shouldn't be selectable"
    end
  end

  test "a file still differing is offered, and counted" do
    with_snapshot do |name|
      SiteSync::History.record!(kind: :sync, outcome: :completed,
        to_local: { deleted: [ "posts/ep.md" ] },
        snapshot: File.join(SiteSync::BackupPaths.local, name))

      get admin_site_sync_history_path

      assert_match "RESTORE SELECTED", response.body
      assert_match 'value="posts/ep.md"', response.body
      assert_match(/1 file still\s+differs/, response.body)
      assert_no_match "ALL CHANGES RESTORED", response.body
    end
  end

  # A path recorded in the log but absent from the snapshot can't be taken from
  # here — saying so beats a checkbox that does nothing.
  test "a path missing from the snapshot says so" do
    with_snapshot do |name|
      SiteSync::History.record!(kind: :sync, outcome: :completed,
        to_local: { deleted: [ "posts/never-captured.md" ] },
        snapshot: File.join(SiteSync::BackupPaths.local, name))

      get admin_site_sync_history_path

      assert_match "Not in restore point", response.body
      assert_no_match 'value="posts/never-captured.md"', response.body
    end
  end

  # A resolve is the answer to a pause, so it reads as an outcome.
  test "a resolve event is badged Resolved" do
    SiteSync::History.record!(kind: :resolve, outcome: :completed,
      to_live: { added: [ "posts/a.md" ] }, to_local: { deleted: [ "posts/b.md" ] })

    get admin_site_sync_history_path

    assert_match "Resolved", response.body
    assert_match "text-green-800", response.body
    assert_match "2 files", response.body
  end

  test "a blocked sync says nothing moved" do
    SiteSync::History.record!(kind: :sync, outcome: :blocked, error: "2 unresolved conflict(s)")

    get admin_site_sync_history_path

    assert_match "nothing moved", response.body
    assert_match "2 unresolved", response.body
  end
end
