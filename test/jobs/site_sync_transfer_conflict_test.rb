require "test_helper"

# The reconciler-driven guard on SiteSyncTransferJob: a real conflict
# STOPS the sync (nothing overwritten) and surfaces on the status; an
# unreachable peer refuses to sync blind; a clean run pushes only the
# safe local-only changes.
class SiteSyncTransferConflictTest < ActiveSupport::TestCase
  def e(size, mtime)
    { "size" => size, "mtime" => mtime }
  end

  def status
    Rails.cache.read(SiteSyncTransferJob::STATUS_CACHE_KEY)
  end

  def setup
    Rails.cache.delete(SiteSyncTransferJob::STATUS_CACHE_KEY)
    # Neutralise the post-transfer bookkeeping so tests focus on the guard.
    SiteSync::Ledger.stubs(:write_current!)
    SiteSync::Checker.stubs(:clear_cache)
    SiteSync::Exchange.stubs(:reconcile_peer_content!)
    SiteSync::Exchange.stubs(:refresh_peer_ledger!)
    SiteSync::Exchange.stubs(:can_call_peer?).returns(false)
    ContentSync.stubs(:sync_all)
    SiteSync::BackupManager.stubs(:create)
  end

  test "push blocks on a real conflict — status :conflicts, nothing pushed" do
    SiteSync::Ledger.stubs(:recorded).returns("files" => { "a.md" => e(1, 100) })
    SiteSync::Ledger.stubs(:current).returns("a.md" => e(2, 200)) # local edited
    SiteSync::Exchange.stubs(:fetch_peer_manifest).returns("files" => { "a.md" => e(3, 300) }) # peer edited, different size

    transport = mock("transport")
    transport.stubs(:backup_live_to_local!)
    transport.expects(:push_local_to_live!).never
    SiteSync.stubs(:transport).returns(transport)

    SiteSyncTransferJob.perform_now(:push)

    assert_equal :conflicts, status[:state]
    assert_equal 1, status[:conflicts].size
    assert_equal "a.md", status[:conflicts].first["path"]
    assert_equal "edit_edit", status[:conflicts].first["type"]
    assert_equal "live", status[:conflicts].first["newer"] # peer mtime 300 > local 200
  end

  test "push applies only the safe local-only changes when there are no conflicts" do
    base = { "a.md" => e(1, 100) }
    SiteSync::Ledger.stubs(:recorded).returns("files" => base)
    SiteSync::Ledger.stubs(:current).returns("a.md" => e(1, 100), "new.md" => e(1, 100)) # local-only add
    SiteSync::Exchange.stubs(:fetch_peer_manifest).returns("files" => base) # peer unchanged

    captured = {}
    transport = mock("transport")
    transport.stubs(:backup_live_to_local!)
    transport.expects(:push_local_to_live!).with do |diff:, on_progress:|
      captured[:diff] = diff
      true
    end
    SiteSync.stubs(:transport).returns(transport)

    SiteSyncTransferJob.perform_now(:push)

    assert_equal :completed, status[:state]
    assert_equal [ "new.md" ], captured[:diff][:added]
    assert_empty captured[:diff][:deleted]
  end

  test "a peer-only change does not block or push (pull's job); push completes with nothing to send" do
    base = { "a.md" => e(1, 100) }
    SiteSync::Ledger.stubs(:recorded).returns("files" => base)
    SiteSync::Ledger.stubs(:current).returns(base) # local unchanged
    SiteSync::Exchange.stubs(:fetch_peer_manifest).returns("files" => { "a.md" => e(9, 900) }) # peer edited

    transport = mock("transport")
    transport.expects(:push_local_to_live!).never # nothing safe to push
    SiteSync.stubs(:transport).returns(transport)

    SiteSyncTransferJob.perform_now(:push)
    assert_equal :completed, status[:state]
  end

  test "peer unreachable → failed with a clear message, nothing pushed" do
    SiteSync::Ledger.stubs(:recorded).returns("files" => {})
    SiteSync::Ledger.stubs(:current).returns({})
    SiteSync::Exchange.stubs(:fetch_peer_manifest).returns(nil)

    transport = mock("transport")
    transport.expects(:push_local_to_live!).never
    SiteSync.stubs(:transport).returns(transport)

    SiteSyncTransferJob.perform_now(:push)

    assert_equal :failed, status[:state]
    assert_match(/reach the live site/i, status[:error])
  end

  test "sync applies safe changes both ways in one pass" do
    base = { "keep.md" => e(1, 100) }
    SiteSync::Ledger.stubs(:recorded).returns("files" => base)
    SiteSync::Ledger.stubs(:current).returns("keep.md" => e(1, 100), "localnew.md" => e(1, 100)) # local-only add
    SiteSync::Exchange.stubs(:fetch_peer_manifest).returns("files" => base.merge("livenew.md" => e(1, 100))) # peer-only add

    push_diff = nil
    pull_diff = nil
    transport = mock("transport")
    transport.stubs(:backup_live_to_local!)
    transport.stubs(:push_local_to_live!).with { |diff:, on_progress:| push_diff = diff; true }
    transport.stubs(:pull_live_to_local!).with { |diff:, on_progress:| pull_diff = diff; true }
    SiteSync.stubs(:transport).returns(transport)

    SiteSyncTransferJob.perform_now(:sync)

    assert_equal :completed, status[:state]
    assert_equal [ "localnew.md" ], push_diff[:added]
    assert_equal [ "livenew.md" ], pull_diff[:added]
  end

  test "sync blocks on a conflict without transferring either way" do
    SiteSync::Ledger.stubs(:recorded).returns("files" => { "a.md" => e(1, 100) })
    SiteSync::Ledger.stubs(:current).returns("a.md" => e(2, 200))
    SiteSync::Exchange.stubs(:fetch_peer_manifest).returns("files" => { "a.md" => e(3, 300) })

    transport = mock("transport")
    transport.stubs(:backup_live_to_local!)
    transport.expects(:push_local_to_live!).never
    transport.expects(:pull_live_to_local!).never
    SiteSync.stubs(:transport).returns(transport)

    SiteSyncTransferJob.perform_now(:sync)
    assert_equal :conflicts, status[:state]
  end
end
