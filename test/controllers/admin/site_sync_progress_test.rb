# frozen_string_literal: true

require "test_helper"

# While a sync or conflict resolution runs, the page shows the current step
# and a progress line. Conflict resolution used to show "Starting…" the
# whole time, and a large video showed "0 of 5 files" until it finished.
class Admin::SiteSyncProgressTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }
  teardown { Rails.cache.delete(SiteSyncTransferJob::STATUS_CACHE_KEY) }

  def running(attrs)
    Rails.cache.write(SiteSyncTransferJob::STATUS_CACHE_KEY,
      { state: :running, started_at: 2.minutes.ago }.merge(attrs), expires_in: 1.hour)
    get admin_site_sync_path
  end

  test "a conflict resolution shows its step and how much has moved" do
    running(kind: :resolve, step: :pushing_to_live,
            progress: { completed: 1, total: 5, bytes_done: 1_288_490_188, bytes_total: 2_684_354_560 })

    assert_response :success
    assert_match "Conflict resolution in progress", response.body
    assert_match SiteSyncTransferJob::STEPS[:pushing_to_live], response.body
    assert_no_match "Starting…", response.body
    assert_match "1 of 5 files · 1.2 GB of 2.5 GB", response.body
    assert_match "width: 48%", response.body
  end

  test "a large file in flight is named, so a long wait says what it's on" do
    running(kind: :sync, step: :backing_up_live,
            progress: { completed: 0, total: 3, bytes_done: 50, bytes_total: 900,
                        current: "media/video/three-benches.mp4" })

    assert_match %r{data-site-sync-target="progressFile"\s*>media/video/three-benches.mp4</p>}, response.body
  end

  test "no file is named when nothing large is in flight" do
    running(kind: :sync, step: :pushing_to_live, progress: { completed: 1, total: 3 })

    assert_match %r{data-site-sync-target="progressFile" hidden></p>}, response.body
  end

  test "progress without byte counts still reads as files transferred" do
    running(kind: :sync, step: :pulling_from_live, progress: { completed: 2, total: 4 })

    assert_match "2 of 4 files transferred", response.body
    assert_match "width: 50%", response.body
  end
end
