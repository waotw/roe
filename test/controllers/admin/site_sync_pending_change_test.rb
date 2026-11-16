# frozen_string_literal: true

require "test_helper"

# Files the next sync will move open on the Site Sync page before the sync:
# the change it will make, from live's copy (fetched on demand) and the local
# file.
class Admin::SiteSyncPendingChangeTest < ActionDispatch::IntegrationTest
  DIR = "zz-pending-change-test"

  setup do
    sign_in_as(User.take)
    @rel = "#{DIR}/post.md"
    @abs = File.join(RoeSitePaths::SITE_PATH, @rel)
    FileUtils.mkdir_p(File.dirname(@abs))
    File.write(@abs, "title\nlocal line\nend\n")
  end

  teardown { FileUtils.rm_rf(File.join(RoeSitePaths::SITE_PATH, DIR)) }

  def live_has(text)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, DIR))
      File.write(File.join(dir, @rel), text)
      SiteSync::Exchange.stubs(:download_files).returns(SiteSync::TarArchive.pack(root: dir, paths: [ @rel ]))
    end
    SiteSync::Exchange.stubs(:fetch_peer_file_states).returns({ @rel => { "size" => text.bytesize, "mtime" => 1 } })
  end

  test "a local change shows what the next sync does to the live version" do
    live_has("title\nlive line\nend\n")
    get admin_site_sync_pending_change_path(path: @rel, side: "local", frame: "pending_x")

    assert_response :success
    assert_select "turbo-frame#pending_x"
    assert_match(/DIFF:[^<]*the live version/, response.body)
    assert_select ".bg-red-50", text: /live line/
    assert_select ".bg-green-50", text: /local line/
  end

  test "a live change shows what the next sync does to the local version" do
    live_has("title\nlive line\nend\n")
    get admin_site_sync_pending_change_path(path: @rel, side: "live", view: "file")

    assert_match(/FILE:[^<]*live sends to local/, response.body)
    assert_match "live line", response.body
  end

  test "without live's copy it says so rather than showing a wrong diff" do
    SiteSync::Exchange.stubs(:fetch_peer_file_states).returns({})
    SiteSync::Exchange.stubs(:download_files).returns(nil)
    get admin_site_sync_pending_change_path(path: @rel, side: "local")

    assert_match "Couldn't get the live copy to compare", response.body
  end

  test "a file live doesn't have yet needs nothing from live" do
    SiteSync::Exchange.stubs(:fetch_peer_file_states).returns({})
    SiteSync::Exchange.expects(:download_files).returns(nil)
    get admin_site_sync_pending_change_path(path: @rel, side: "local", change: "added")

    assert_match(/FILE:[^<]*local sends to live/, response.body)
  end

  test "a conflict opens on the diff between the two versions" do
    live_has("title\nlive line\nend\n")
    get admin_site_sync_pending_change_path(path: @rel, change: "conflict", frame: "conflict_x")

    assert_select "turbo-frame#conflict_x [data-change-panel=conflict]"
    assert_match "DIFF: red lines are only in the live version, green lines only in the local version.", response.body
    assert_select ".bg-red-50", text: /live line/
    assert_select ".bg-green-50", text: /local line/
  end

  test "a conflict's LIVE tab shows the live version" do
    live_has("title\nlive line\nend\n")
    get admin_site_sync_pending_change_path(path: @rel, change: "conflict", view: "live")

    assert_match "LIVE: the live version.", response.body
    assert_match "live line", response.body
    assert_no_match "local line", response.body
  end

  test "a file deleted on live opens on the local version, with no DIFF" do
    SiteSync::Exchange.stubs(:fetch_peer_file_states).returns({})
    SiteSync::Exchange.stubs(:download_files).returns(nil)
    get admin_site_sync_pending_change_path(path: @rel, change: "conflict", view: "diff")

    assert_match "LOCAL: the local version.", response.body
    assert_no_match ">DIFF<", response.body
  end

  test "paths outside what Site Sync tracks are refused" do
    get admin_site_sync_pending_change_path(path: "../secrets.txt", side: "local")
    assert_response :not_found
    get admin_site_sync_pending_change_path(path: "system/secrets/master.key", side: "local")
    assert_response :not_found
  end

  test "DOWNLOAD sends live's copy as a file" do
    live_has("from live")
    get admin_site_sync_pending_version_path(path: @rel, which: "live")

    assert_equal "from live", response.body
    assert_match "attachment", response.headers["Content-Disposition"]
  end
end
