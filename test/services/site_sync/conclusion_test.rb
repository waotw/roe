# frozen_string_literal: true

require "test_helper"

# The bug this replaced: after a sync that worked, the banner still said
# "local differs from live" while the Site Sync page said the two were in
# sync. Four surfaces each compared fingerprints on their own, and only one
# of them also asked PeerAgreement for a second opinion.
class SiteSync::ConclusionTest < ActiveSupport::TestCase
  setup do
    @synced_at = Time.current
    stub_local(fingerprint: "local-fp", synced_at: @synced_at)
    SiteSync::Exchange.stubs(:can_call_peer?).returns(true)
    SiteSync::Exchange.stubs(:peer_reachable?).returns(true)
  end

  def stub_local(fingerprint:, synced_at:)
    SiteSync::Ledger.stubs(:fingerprint_for).returns(fingerprint)
    SiteSync::Ledger.stubs(:recorded).returns({ "version" => synced_at.utc.iso8601 })
  end

  def peer(fingerprint:, ago: nil, at: nil)
    { fingerprint: fingerprint, received_at: at || (@synced_at + 1.minute) - (ago || 0) }
  end

  test "matching fingerprints from a peer that spoke after our last sync is in sync" do
    conclusion = SiteSync::Conclusion.current(peer_state: peer(fingerprint: "local-fp"))

    assert_predicate conclusion, :in_sync?
  end

  test "a peer that last spoke before our own last sync is unknown, not drifted" do
    # The exact shape of the reported bug: the sync finished and rewrote the
    # ledger, but the cached peer fingerprint still describes what live held
    # beforehand. Comparing them reports drift on a sync that worked.
    stale = peer(fingerprint: "old-live-fp", at: @synced_at - 10.minutes)

    conclusion = SiteSync::Conclusion.current(peer_state: stale)

    assert_predicate conclusion, :unknown?
    refute_predicate conclusion, :out_of_sync?
    assert_predicate conclusion, :undecided?, "peer is configured, so this is worth explaining"
  end

  test "differing fingerprints the peer can't reconcile are out of sync" do
    SiteSync::PeerAgreement.stubs(:verify).returns(nil)

    conclusion = SiteSync::Conclusion.current(peer_state: peer(fingerprint: "other-fp"))

    assert_predicate conclusion, :out_of_sync?
  end

  test "differing fingerprints that are only mtime skew are in sync" do
    # PeerAgreement exists because the fingerprint covers mtime: identical
    # bytes with different timestamps read as a difference, and warn about a
    # drift no sync can clear. Only one surface used to ask.
    SiteSync::PeerAgreement.stubs(:verify).returns(
      SiteSync::PeerAgreement::Result.new(in_sync: true, differing: [ "a.md" ], confirmed_identical: [ "a.md" ])
    )

    conclusion = SiteSync::Conclusion.current(peer_state: peer(fingerprint: "other-fp"))

    assert_predicate conclusion, :in_sync?
    assert_predicate conclusion.agreement, :mtime_only?
  end

  test "no peer configured is unknown but not worth explaining" do
    SiteSync::Exchange.stubs(:can_call_peer?).returns(false)

    conclusion = SiteSync::Conclusion.current(peer_state: peer(fingerprint: "local-fp"))

    assert_predicate conclusion, :unknown?
    refute_predicate conclusion, :undecided?
  end

  test "never having heard from the peer is unknown" do
    conclusion = SiteSync::Conclusion.current(peer_state: nil, refresh: false)
    SiteSync::Exchange.stubs(:peer_state).returns(nil)

    assert_predicate conclusion, :unknown?
    assert_nil conclusion.as_of
  end

  test "carries the freshness the surfaces need to be honest about it" do
    conclusion = SiteSync::Conclusion.current(peer_state: peer(fingerprint: "local-fp"))

    assert_equal @synced_at.to_i, conclusion.last_synced_at.to_i
    assert_equal (@synced_at + 1.minute).to_i, conclusion.as_of.to_i
  end
end
