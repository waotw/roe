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

  test "a conflict resolution shows its step and how much has been sent" do
    running(kind: :resolve, step: :pushing_to_live,
            progress: { completed: 1, total: 5, bytes_done: 1_288_490_188, bytes_total: 2_684_354_560 })

    assert_response :success
    assert_match "Conflict resolution in progress", response.body
    assert_match SiteSyncTransferJob::STEPS[:pushing_to_live], response.body
    assert_no_match "Starting…", response.body
    assert_match "1 of 5 files · 1.2 GB of 2.5 GB sent", response.body
    assert_match "width: 48%", response.body
  end

  test "progress without byte counts still reads as files transferred" do
    running(kind: :sync, step: :pulling_from_live, progress: { completed: 2, total: 4 })

    assert_match "2 of 4 files transferred", response.body
    assert_match "width: 50%", response.body
  end
end

# The confirmation screen names files whose live copy is too large for the
# backup a sync takes first, so the choice is made knowing there's no copy.
class Admin::SiteSyncNotBackedUpTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }
  teardown { Rails.cache.delete(SiteSyncTransferJob::STATUS_CACHE_KEY) }

  def paused_with(conflicts)
    Rails.cache.write(SiteSyncTransferJob::STATUS_CACHE_KEY,
      { state: :conflicts, kind: :sync, conflicts: conflicts }, expires_in: 1.hour)
    get admin_site_sync_path
  end

  def deleted_here(path, live_size)
    { "path" => path, "type" => "delete_edit", "local" => nil,
      "peer" => { "size" => live_size, "mtime" => 1 }, "newer" => "live" }
  end

  test "a large file deleted here says live's copy won't be backed up" do
    big = SiteSync::BackupPolicy::LIVE_BACKUP_MAX_BYTES + 1
    paused_with([ deleted_here("media/video/clip.mov", big), deleted_here("posts/a.md", 100) ])

    assert_response :success
    assert_equal 1, response.body.scan("too large to back up before syncing").size
    assert_match "download it from the live site", response.body
  end

  test "video web versions are not named — they're made again from the original" do
    big = SiteSync::BackupPolicy::LIVE_BACKUP_MAX_BYTES + 1
    paused_with([ deleted_here("media/video/variants/clip-1080p.mp4", big) ])

    assert_no_match "too large to back up", response.body
  end
end
