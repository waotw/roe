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

  test "a file only this computer's record can place shows as a live change, not as unexplained" do
    result = SiteSync::PeerAgreement::Result.new(in_sync: false, differing: [], confirmed_identical: [],
                                                 on_live: { modified: [ "posts/test-post-for-sync.md" ], added: [], deleted: [] })
    SiteSync::Conclusion.stubs(:current).returns(conclusion(:out_of_sync).tap { |c| c.agreement = result })
    SiteSync::Ledger.stubs(:recorded).returns({ "files" => {} }) # synced before, so not a first sync
    get admin_site_sync_path

    assert_match "1 file to sync", overview
    assert_match "has changes to pull in", response.body
    assert_no_match "neither side", response.body
  end

  test "each pending file opens in place, and changes read as changed" do
    result = SiteSync::PeerAgreement::Result.new(in_sync: false, differing: [], confirmed_identical: [],
                                                 on_live: { modified: [ "posts/a.md" ], added: [], deleted: [] })
    SiteSync::Conclusion.stubs(:current).returns(conclusion(:out_of_sync).tap { |c| c.agreement = result })
    SiteSync::Ledger.stubs(:recorded).returns({ "files" => {} })
    get admin_site_sync_path

    assert_select "li[data-controller=history-panel] a[href=?]",
                  admin_site_sync_pending_change_path(path: "posts/a.md", side: "live", change: "changed",
                                                      frame: "pending_live_#{Digest::SHA1.hexdigest('posts/a.md')[0, 12]}")
    assert_match "Changed (1)", response.body
    assert_no_match(/>\s*modified\s*</, response.body)
  end

  test "Roe's documentation folds into one row that opens to its files" do
    SiteSync::Checker.stubs(:status).returns(
      state: :local_drift, local: { modified: [ "documentation/roe/system-site_sync.md" ], added: [], deleted: [] }, recorded_at: Time.current
    )
    SiteSync::Conclusion.stubs(:current).returns(conclusion(:out_of_sync))
    SiteSync::Ledger.stubs(:recorded).returns({ "files" => {} })
    get admin_site_sync_path

    assert_select "details summary", text: /Roe documentation — 1 file changed/
    assert_select "details li[data-controller=history-panel] a", text: /documentation\/roe\/system-site_sync.md/
  end
end
