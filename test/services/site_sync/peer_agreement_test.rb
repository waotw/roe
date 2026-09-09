require "test_helper"

# The Site Sync fingerprint covers size + mtime, so a file with identical bytes
# and a different timestamp counted as a difference — and produced a warning
# the user couldn't clear, because with no drift on either side a sync has
# nothing to transfer and nothing rewrites those mtimes.
class SiteSync::PeerAgreementTest < ActiveSupport::TestCase
  FP_A = "aaa"
  FP_B = "bbb"

  setup { Rails.cache.clear }

  def stub_manifests(local:, peer:)
    SiteSync::Ledger.stubs(:current).returns(local)
    SiteSync::Exchange.stubs(:fetch_peer_manifest).returns({ "files" => peer })
  end

  def entry(size, mtime) = { "size" => size, "mtime" => mtime }

  # The case that produced the unclearable warning.
  test "identical bytes with different mtimes count as in sync" do
    stub_manifests(local: { "a.md" => entry(10, 100) }, peer: { "a.md" => entry(10, 200) })
    SiteSync::Reconciler.stubs(:hashes_for).returns({ "a.md" => "sha1" })
    SiteSync::Exchange.stubs(:fetch_peer_file_hashes).returns({ "a.md" => "sha1" })

    result = SiteSync::PeerAgreement.verify(local_fingerprint: FP_A, peer_fingerprint: FP_B)

    assert result.in_sync
    assert_equal [ "a.md" ], result.confirmed_identical
  end

  test "same size but different bytes is a real difference" do
    stub_manifests(local: { "a.md" => entry(10, 100) }, peer: { "a.md" => entry(10, 200) })
    SiteSync::Reconciler.stubs(:hashes_for).returns({ "a.md" => "sha1" })
    SiteSync::Exchange.stubs(:fetch_peer_file_hashes).returns({ "a.md" => "sha2" })

    result = SiteSync::PeerAgreement.verify(local_fingerprint: FP_A, peer_fingerprint: FP_B)

    assert_not result.in_sync
    assert_equal [ "a.md" ], result.differing
  end

  # A size difference already proves the content differs — don't pay for hashes.
  test "a size difference short-circuits without hashing" do
    stub_manifests(local: { "a.md" => entry(10, 100) }, peer: { "a.md" => entry(20, 100) })
    SiteSync::Reconciler.expects(:hashes_for).never
    SiteSync::Exchange.expects(:fetch_peer_file_hashes).never

    result = SiteSync::PeerAgreement.verify(local_fingerprint: FP_A, peer_fingerprint: FP_B)

    assert_not result.in_sync
    assert_equal [ "a.md" ], result.differing
  end

  test "a path on one side only is a real difference" do
    stub_manifests(local: { "a.md" => entry(10, 100) }, peer: {})
    SiteSync::Reconciler.expects(:hashes_for).never

    result = SiteSync::PeerAgreement.verify(local_fingerprint: FP_A, peer_fingerprint: FP_B)

    assert_not result.in_sync
    assert_equal [ "a.md" ], result.differing
  end

  # Claiming a sync that didn't happen is worse than an extra warning.
  test "an unavailable peer hash counts as differing" do
    stub_manifests(local: { "a.md" => entry(10, 100) }, peer: { "a.md" => entry(10, 200) })
    SiteSync::Reconciler.stubs(:hashes_for).returns({ "a.md" => "sha1" })
    SiteSync::Exchange.stubs(:fetch_peer_file_hashes).returns({})

    assert_not SiteSync::PeerAgreement.verify(local_fingerprint: FP_A, peer_fingerprint: FP_B).in_sync
  end

  test "an unreachable peer returns nil rather than a verdict" do
    SiteSync::Exchange.stubs(:fetch_peer_manifest).returns(nil)

    assert_nil SiteSync::PeerAgreement.verify(local_fingerprint: FP_A, peer_fingerprint: FP_B)
  end

  test "a blank fingerprint is not compared" do
    SiteSync::Exchange.expects(:fetch_peer_manifest).never

    assert_nil SiteSync::PeerAgreement.verify(local_fingerprint: nil, peer_fingerprint: FP_B)
  end

  # Reloading the page shouldn't re-hash.
  test "the verdict is cached per fingerprint pair" do
    stub_manifests(local: { "a.md" => entry(10, 100) }, peer: { "a.md" => entry(10, 200) })
    SiteSync::Reconciler.stubs(:hashes_for).returns({ "a.md" => "sha1" })
    SiteSync::Exchange.expects(:fetch_peer_file_hashes).once.returns({ "a.md" => "sha1" })

    2.times { SiteSync::PeerAgreement.verify(local_fingerprint: FP_A, peer_fingerprint: FP_B) }
  end
end
