# frozen_string_literal: true

require "test_helper"

# Sync History from the version store: what each sync moved, each file
# opened in place (FILE, DIFF, COMPARE TO CURRENT), a file's own log, and
# REWIND on the newest sync.
class Admin::SiteSyncVersionHistoryTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  DIR = "zz-version-history-test"

  setup do
    sign_in_as(User.take)
    FileUtils.rm_rf(SiteSync::Versions.root)
    FileUtils.mkdir_p(File.join(RoeSitePaths::SITE_PATH, DIR))
    ContentSync.stubs(:sync_all)
    @rel = "#{DIR}/post.md"
    File.write(path, "title\nlocal line\nend\n")
    recorder = SiteSync::Versions::Recorder.new
    recorder.save_local!([ @rel ])
    File.write(path, "title\nlive line\nend\n")
    @event = recorder.finish!(kind: :sync, outcome: :completed)
    @change = SiteSync::Versions.history_of(@rel).first
  end

  teardown do
    Rails.cache.delete(SiteSyncTransferJob::STATUS_CACHE_KEY)
    FileUtils.rm_rf(SiteSync::Versions.root)
    FileUtils.rm_rf(File.join(RoeSitePaths::SITE_PATH, DIR))
  end

  def path = File.join(RoeSitePaths::SITE_PATH, @rel)

  def second_sync
    recorder = SiteSync::Versions::Recorder.new
    recorder.save_local!([ @rel ])
    File.write(path, "title\nnewer line\nend\n")
    recorder.finish!(kind: :sync, outcome: :completed)
  end

  test "the history lists what each sync moved, with no checkboxes and REWIND on the newest" do
    get admin_site_sync_history_path
    assert_response :success
    assert_select "input[type=checkbox]", 0
    assert_match "↓ LIVE TO LOCAL · 1", response.body
    assert_match "↑ LOCAL TO LIVE · 0", response.body
    frame = "event_#{@event}_panel"
    assert_select "a[href=?][data-turbo-frame=?]", admin_site_sync_history_change_path(@change[:id], frame: frame), frame
    assert_select "a[href=?]", admin_site_sync_rewind_path(@event), text: "REWIND"
  end

  test "only the newest sync has REWIND" do
    newer = second_sync
    get admin_site_sync_history_path
    assert_select "a[href=?]", admin_site_sync_rewind_path(newer), text: "REWIND"
    assert_select "a[href=?]", admin_site_sync_rewind_path(@event), count: 0
  end

  test "a file opens in place with the change it made, and HISTORY" do
    get admin_site_sync_history_change_path(@change[:id], frame: "event_#{@event}_panel")
    assert_response :success
    assert_select "turbo-frame#event_#{@event}_panel"
    assert_match "DIFF: these are the changes made to the local version of this file.", response.body
    assert_select ".bg-red-50", text: /local line/
    assert_select ".bg-green-50", text: /live line/
    assert_select "a[href=?]", admin_site_sync_history_file_path(path: @rel), text: "HISTORY"
    assert_select "a", text: "COMPARE TO CURRENT", count: 0

    get admin_site_sync_history_change_path(@change[:id], view: "file")
    assert_match "FILE: the local version after this sync.", response.body
    assert_match "live line", response.body
  end

  test "COMPARE TO CURRENT is offered once the file has changed since" do
    File.write(path, "title\nedited since\nend\n")
    get admin_site_sync_history_change_path(@change[:id], view: "current")
    assert_select "a", text: "COMPARE TO CURRENT"
    assert_select ".bg-red-50", text: /live line/
    assert_select ".bg-green-50", text: /edited since/
  end

  test "a file's history is a dated log, newest first, with NOW on the version in place" do
    second_sync
    get admin_site_sync_history_file_path(path: @rel)
    assert_response :success
    assert_select "details", 2
    assert_select "details summary", text: /Came down from live/, count: 2
    assert_select "details:first-of-type summary", text: /NOW/
    assert_select "turbo-frame[loading=lazy]", 2
  end

  test "DOWNLOAD sends the version as a file; only images open in the page" do
    get admin_site_sync_history_version_path(@change[:id], version: "before")
    assert_response :success
    assert_equal "title\nlocal line\nend\n", response.body
    assert_match "attachment", response.headers["Content-Disposition"]

    get admin_site_sync_history_version_path(@change[:id], version: "after", inline: 1)
    assert_match "attachment", response.headers["Content-Disposition"], "not an image, so never shown inline"
  end

  test "REWIND shows what will happen first, and warns about changes made since" do
    SiteSync::Exchange.stubs(:fetch_peer_manifest).returns({ "files" => {} })
    File.write(path, "edited since")

    get admin_site_sync_rewind_path(@event)
    assert_response :success
    assert_match "The live and local site files will return to exactly as they were before this sync.", response.body
    assert_select "#changed-since", text: /#{Regexp.escape(@rel)}/
    assert_match "ON LOCAL", response.body
    assert_select "form[action=?] button", admin_site_sync_rewind_path(@event), text: "REWIND"
  end

  test "REWIND can't start without live" do
    SiteSync::Exchange.stubs(:fetch_peer_manifest).returns(nil)
    get admin_site_sync_rewind_path(@event)
    assert_match "Couldn't reach the live site", response.body
    assert_select "form[action=?]", admin_site_sync_rewind_path(@event), count: 0
  end

  test "pressing REWIND starts the job and shows its progress on Site Sync" do
    Rails.cache.stubs(:write)
    Rails.cache.expects(:write).with { |key, value, *| key == SiteSyncTransferJob::STATUS_CACHE_KEY && value[:kind] == :rewind && value[:state] == :running }
    assert_enqueued_with(job: SiteSyncRewindJob, args: [ @event ]) do
      post admin_site_sync_rewind_path(@event)
    end
    assert_redirected_to admin_site_sync_path
  end

  test "an older sync can't be rewound" do
    second_sync
    assert_no_enqueued_jobs(only: SiteSyncRewindJob) do
      post admin_site_sync_rewind_path(@event)
    end
    assert_equal "Only the newest sync can be rewound.", flash[:alert]
  end

  test "after a rewind, Site Sync says the sites are out of sync" do
    Rails.cache.stubs(:read).returns(nil)
    Rails.cache.stubs(:read).with(SiteSyncTransferJob::STATUS_CACHE_KEY)
               .returns({ state: :completed, kind: :rewind, started_at: Time.current, event_at: Time.current })
    get admin_site_sync_path
    assert_select "#rewind-finished", text: /Live and local are out\s+of sync/
  end

  test "Site Sync links to the history with a button" do
    get admin_site_sync_path
    assert_select "a[href=?]", admin_site_sync_history_path, text: "SYNC HISTORY"
  end
end
