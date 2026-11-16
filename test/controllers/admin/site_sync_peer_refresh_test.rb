# frozen_string_literal: true

require "test_helper"

# The Site Sync page asks live again in the background when its answer is
# more than a minute old (Exchange.refresh_if_stale). The page then waits for
# that answer and redraws, so a change on live shows without pressing
# REFRESH SYNC STATUS.
class Admin::SiteSyncPeerRefreshTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    Rails.cache.delete(SiteSyncTransferJob::STATUS_CACHE_KEY)
    SiteSync::Exchange.stubs(:can_call_peer?).returns(true)
    SiteSync::Exchange.stubs(:peer_url).returns("https://live.example")
    SiteSync::Exchange.stubs(:peer_label).returns("Live site")
    SiteSync::Checker.stubs(:status).returns(
      state: :clean, local: { modified: [], added: [], deleted: [] }, recorded_at: Time.current
    )
  end

  teardown { Rails.cache.delete(SiteSyncTransferJob::STATUS_CACHE_KEY) }

  def state(received_at)
    { env: "production", fingerprint: "f", recorded_fingerprint: "f", received_at: received_at,
      drift: { modified: [], added: [], deleted: [] } }
  end

  test "an old answer asks live again and the page waits for the new one" do
    SiteSync::Exchange.stubs(:peer_state).returns(state(5.minutes.ago))
    SiteSyncExchangeJob.expects(:perform_later).once
    get admin_site_sync_path

    assert_select "[data-controller='site-sync-refresh'][data-site-sync-refresh-url-value=?]", admin_site_sync_peer_status_path
  end

  test "a fresh answer neither asks nor waits" do
    SiteSync::Exchange.stubs(:peer_state).returns(state(10.seconds.ago))
    SiteSyncExchangeJob.expects(:perform_later).never
    get admin_site_sync_path

    assert_select "[data-controller='site-sync-refresh']", 0
  end

  test "it doesn't wait while a transfer runs" do
    SiteSync::Exchange.stubs(:peer_state).returns(state(5.minutes.ago))
    Rails.cache.write(SiteSyncTransferJob::STATUS_CACHE_KEY, { state: :running, kind: :sync, step: :checking, started_at: Time.current })
    get admin_site_sync_path

    assert_select "[data-controller='site-sync-refresh']", 0
  end

  test "peer_status reports when live last answered" do
    at = 30.seconds.ago
    SiteSync::Exchange.stubs(:peer_state).returns(state(at))
    get admin_site_sync_peer_status_path

    assert_equal at.to_i, JSON.parse(response.body)["received_at"]
  end
end
