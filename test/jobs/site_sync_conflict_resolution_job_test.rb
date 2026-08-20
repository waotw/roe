require "test_helper"

# The resolution job turns each admin choice ("local" | "live") plus the
# conflict's type into a concrete per-file action, then applies it via the
# transport. The mapping is the data-sensitive bit — pin it down.
class SiteSyncConflictResolutionJobTest < ActiveSupport::TestCase
  def setup
    SiteSync::Ledger.stubs(:write_current!)
    SiteSync::Checker.stubs(:clear_cache)
    SiteSync::Exchange.stubs(:reconcile_peer_content!)
    SiteSync::Exchange.stubs(:refresh_peer_ledger!)
    SiteSync::Exchange.stubs(:can_call_peer?).returns(false)
    ContentSync.stubs(:sync_all)
    SiteSync::BackupManager.stubs(:create)
    Rails.cache.delete(SiteSyncTransferJob::STATUS_CACHE_KEY)
  end

  test "maps each (type, winner) to the correct push/pull add/delete action" do
    conflicts = [
      { "path" => "ee.md",  "type" => "edit_edit" },
      { "path" => "de.md",  "type" => "delete_edit" },
      { "path" => "ed.md",  "type" => "edit_delete" },
      { "path" => "ee2.md", "type" => "edit_edit" }
    ]
    resolutions = { "ee.md" => "local", "de.md" => "local", "ed.md" => "live", "ee2.md" => "live" }

    push_diff = nil
    pull_diff = nil
    transport = mock("transport")
    transport.stubs(:backup_live_to_local!)
    transport.stubs(:push_local_to_live!).with { |diff:| push_diff = diff; true }
    transport.stubs(:pull_live_to_local!).with { |diff:| pull_diff = diff; true }
    SiteSync.stubs(:transport).returns(transport)

    SiteSyncConflictResolutionJob.perform_now(resolutions, conflicts)

    # local-wins → live gets local's version:
    #   ee.md (edit/edit) → push add;  de.md (delete/edit) → push delete
    assert_equal [ "ee.md" ], push_diff[:added]
    assert_equal [ "de.md" ], push_diff[:deleted]

    # live-wins → local takes live's version:
    #   ee2.md (edit/edit) → pull add;  ed.md (edit/delete) → pull delete
    assert_equal [ "ee2.md" ], pull_diff[:added]
    assert_equal [ "ed.md" ], pull_diff[:deleted]

    assert_equal :completed, Rails.cache.read(SiteSyncTransferJob::STATUS_CACHE_KEY)[:state]
  end

  test "an all-local resolution never touches the pull path" do
    conflicts   = [ { "path" => "a.md", "type" => "edit_edit" } ]
    resolutions = { "a.md" => "local" }

    transport = mock("transport")
    transport.stubs(:backup_live_to_local!)
    transport.expects(:push_local_to_live!).once
    transport.expects(:pull_live_to_local!).never
    SiteSync.stubs(:transport).returns(transport)

    SiteSyncConflictResolutionJob.perform_now(resolutions, conflicts)
  end


  # The job clears its status caches, then keeps working — ContentSync can
  # rewrite a file on its way through. Anything that read our status in between
  # cached an answer computed before that happened: an admin page render, or the
  # layout banner on any navigation, both of which "refresh the page to check
  # progress" invites. Left in place, the banner reports drift on a sync that
  # worked, and syncing again clears it — which is what made the first one look
  # like it hadn't taken.
  test "a status cached after the job starts does not survive it" do
    transport = mock("transport")
    transport.stubs(:backup_live_to_local!)
    transport.stubs(:push_local_to_live!)
    transport.stubs(:pull_live_to_local!)
    SiteSync.stubs(:transport).returns(transport)

    # Stands in for a page render landing while the job is still going. Hung off
    # the last step that can touch /site, which is where the old clear was too
    # early to help.
    SiteSync::Checker.unstub(:clear_cache)
    ContentSync.unstub(:sync_all)
    ContentSync.stubs(:sync_all).with do
      Rails.cache.write("site_sync:status", { state: :local_drift })
      Rails.cache.write("site_sync:current_fingerprint", "stale")
      true
    end

    SiteSyncConflictResolutionJob.perform_now(
      { "ee.md" => "live" }, [ { "path" => "ee.md", "type" => "edit_edit" } ]
    )

    assert_nil Rails.cache.read("site_sync:status"),
      "the status cached mid-job should have been cleared at the end"
    assert_nil Rails.cache.read("site_sync:current_fingerprint")
  end
end
