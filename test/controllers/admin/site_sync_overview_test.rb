# frozen_string_literal: true

require "test_helper"

# The overview at the top of the Site Sync page and the "Changes to sync"
# panel below it read one answer (Admin::SiteSyncController#live_sync_overview).
# The top line used to look only at this side's record, so it said "All up to
# date · in sync" while the panel listed two files that differed from live.
class Admin::SiteSyncOverviewTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    Rails.cache.delete(SiteSyncTransferJob::STATUS_CACHE_KEY)

    SiteSync::Exchange.stubs(:can_call_peer?).returns(true)
    SiteSync::Exchange.stubs(:peer_url).returns("https://live.example")
    SiteSync::Exchange.stubs(:peer_reachable?).returns(true)
    SiteSync::Exchange.stubs(:refresh_if_stale).returns(peer_state)
    SiteSync::Exchange.stubs(:peer_state).returns(peer_state)
    SiteSync::Exchange.stubs(:peer_has_drift?).returns(false)
    SiteSync::Exchange.stubs(:peer_label).returns("Live site")
    SiteSync::Checker.stubs(:status).returns(
      state: :clean, local: { modified: [], added: [], deleted: [] }, recorded_at: Time.current
    )
  end

  def peer_state
    { env: "production", fingerprint: "peer", recorded_fingerprint: "peer", received_at: 1.minute.ago,
      drift: { modified: [], added: [], deleted: [] } }
  end

  def conclusion(state, differing: [])
    SiteSync::Conclusion.new(
      state: state, as_of: 1.minute.ago, local_fingerprint: "local", peer_fingerprint: "peer",
      agreement: SiteSync::PeerAgreement::Result.new(in_sync: state == :in_sync, differing: differing, confirmed_identical: []),
      peer_reachable: true, configured: true, last_synced_at: 12.hours.ago
    )
  end

  def overview = response.body[/<h3[^>]*>\s*(All up to date|Pending changes)\s*<\/h3>.*?<\/ul>/m]

  test "files that differ from live show at the top, not just in the panel" do
    SiteSync::Conclusion.stubs(:current).returns(
      conclusion(:out_of_sync, differing: %w[system/global/content.yml media/video/variants/three-benches-720p.mp4])
    )
    get admin_site_sync_path

    assert_response :success
    assert_match "Pending changes", overview
    assert_match "2 files to sync", overview
    assert_no_match(/in sync/, overview)
    assert_match "system/global/content.yml", response.body
  end

  test "in sync on both counts reads as all up to date" do
    SiteSync::Conclusion.stubs(:current).returns(conclusion(:in_sync))
    get admin_site_sync_path

    assert_match "All up to date", overview
    assert_match "in sync", overview
    assert_no_match "Changes to sync", response.body
  end

  test "live changes count at the top too" do
    SiteSync::Exchange.stubs(:peer_has_drift?).returns(true)
    SiteSync::Exchange.stubs(:refresh_if_stale).returns(
      peer_state.merge(drift: { modified: [ "posts/a.md" ], added: [], deleted: [] })
    )
    SiteSync::Conclusion.stubs(:current).returns(conclusion(:out_of_sync, differing: [ "posts/a.md" ]))
    get admin_site_sync_path

    assert_match "1 file to sync", overview
  end

  # Live last answered before our latest sync: we can't vouch either way, and
  # green "in sync" would be a claim.
  test "an answer from before the last sync reads as checking, not in sync" do
    SiteSync::Conclusion.stubs(:current).returns(conclusion(:unknown))
    get admin_site_sync_path

    assert_match "checking with live", overview
    assert_no_match(/>in sync/, overview)
  end
end
