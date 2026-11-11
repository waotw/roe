# frozen_string_literal: true

require "test_helper"

# Sync History from the version store: every change can be undone, and the
# whole site can go back to just after any sync.
class Admin::SiteSyncVersionHistoryTest < ActionDispatch::IntegrationTest
  DIR = "zz-version-history-test"

  setup do
    sign_in_as(User.take)
    FileUtils.rm_rf(SiteSync::Versions.root)
    FileUtils.mkdir_p(File.join(RoeSitePaths::SITE_PATH, DIR))
    ContentSync.stubs(:sync_all)
    @rel = "#{DIR}/post.md"
    File.write(path, "mine")
    recorder = SiteSync::Versions::Recorder.new
    recorder.save_local!([ @rel ])
    File.write(path, "live's")
    @event = recorder.finish!(kind: :sync, outcome: :completed)
  end

  teardown do
    FileUtils.rm_rf(SiteSync::Versions.root)
    FileUtils.rm_rf(File.join(RoeSitePaths::SITE_PATH, DIR))
  end

  def path = File.join(RoeSitePaths::SITE_PATH, @rel)

  test "the history lists each change with a way to undo it" do
    get admin_site_sync_history_path
    assert_response :success
    assert_select "input[name='change_ids[]']", 1
    assert_match @rel, response.body
    assert_match "RESTORE SELECTED", response.body
    assert_select "a[href=?]", admin_site_sync_history_point_path(@event)
  end

  test "restoring selected changes puts the old version back" do
    change = SiteSync::Versions.history_of(@rel).first
    post admin_restore_site_sync_versions_path, params: { change_ids: [ change[:id] ] }

    assert_redirected_to admin_site_sync_history_path
    assert_equal "mine", File.read(path)
    assert_match "Restored 1 file", flash[:notice]
  end

  test "a restore point previews what it would change, then restores it" do
    File.write(path, "edited since")
    get admin_site_sync_history_point_path(@event)
    assert_response :success
    assert_match @rel, response.body
    assert_match "RESTORE 1 FILE", response.body

    post admin_restore_site_sync_history_point_path(@event)
    assert_equal "live's", File.read(path)
  end
end
