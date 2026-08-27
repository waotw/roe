# frozen_string_literal: true

require "test_helper"

# How Site Sync deleted files it was supposed to be protecting.
#
# Resolving only SOME of a blocked sync's conflicts re-baselines ALL of the
# local tree. The unresolved paths are skipped by the plan but still recorded
# as "last known synced" — so on the next sync they look like files the peer
# deleted, and the peer's non-existent deletion gets applied locally.
#
# Observed 2026-08-26: two syncs blocked (9 then 10 conflicts), a partial
# resolution ran, and the next sync pulled with no push step and removed 9
# podcast episodes and all 23 audio files from the local site.
class SiteSync::PartialResolutionDataLossTest < ActiveSupport::TestCase
  def entry(size = 10, mtime = 1_700_000_000) = { "size" => size, "mtime" => mtime }

  # ── Link 1: what the reconciler does with a bad baseline ──────────────────

  # This is correct three-way behaviour *if the baseline is true*. It means
  # "we both had this file, the peer removed it, so remove it here." The
  # danger is entirely in how the baseline gets written.
  test "a file in the baseline and absent on the peer is deleted locally" do
    result = SiteSync::Reconciler.reconcile(
      baseline: { "posts/ep.md" => entry },
      local:    { "posts/ep.md" => entry },
      peer:     {}
    )

    assert_includes result.pull_delete, "posts/ep.md"
    assert_empty result.push, "it isn't even offered to the peer"
    assert_empty result.conflicts, "and it isn't flagged for the user"
  end

  # The same file, correctly absent from the baseline, is pushed instead —
  # which is what should have happened.
  test "the same file NOT in the baseline is pushed to the peer" do
    result = SiteSync::Reconciler.reconcile(
      baseline: {},
      local:    { "posts/ep.md" => entry },
      peer:     {}
    )

    assert_includes result.push, "posts/ep.md"
    assert_empty result.pull_delete
  end

  # ── Link 2: how the bad baseline gets written ────────────────────────────

  # An unresolved conflict produces no action at all — correct on its own.
  test "resolving nothing plans nothing" do
    conflicts = [ { "path" => "posts/ep.md", "type" => "edit_delete" } ]
    plan = SiteSyncConflictResolutionJob.new.send(:build_plan, {}, conflicts)

    assert_equal [], plan.values.flatten, "an unresolved conflict must not act"
  end

  test "resolving one of two leaves the other unplanned" do
    conflicts = [
      { "path" => "posts/kept.md", "type" => "edit_delete" },
      { "path" => "posts/ep.md",   "type" => "edit_delete" }
    ]
    plan = SiteSyncConflictResolutionJob.new.send(:build_plan, { "posts/kept.md" => "local" }, conflicts)

    assert_equal [ "posts/kept.md" ], plan[:push_add]
    assert_equal [], plan.values.flatten - [ "posts/kept.md" ],
      "posts/ep.md is untouched — it stays local-only and off the peer"
  end

  # The fix: only settled paths enter the baseline.
  test "an unresolved path is left out of the new baseline" do
    job = SiteSyncConflictResolutionJob.new
    recorded = { "posts/old.md" => entry }
    current  = { "posts/old.md" => entry, "posts/kept.md" => entry(20), "posts/unresolved.md" => entry(30) }

    SiteSync::Ledger.stubs(:recorded).returns({ "files" => recorded })
    SiteSync::Ledger.stubs(:current).returns(current)
    written = nil
    SiteSync::Ledger.stubs(:write_manifest!).with { |m| written = m; true }

    job.send(:rebaseline!, { push_add: [ "posts/kept.md" ], push_delete: [], pull_add: [], pull_delete: [] })

    assert_includes written.keys, "posts/kept.md", "the settled path is baselined"
    assert_includes written.keys, "posts/old.md",  "the previous baseline is preserved"
    assert_not_includes written.keys, "posts/unresolved.md",
      "an unresolved path in the baseline is what caused the deletion"
  end

  test "a settled deletion is removed from the baseline" do
    job = SiteSyncConflictResolutionJob.new
    SiteSync::Ledger.stubs(:recorded).returns({ "files" => { "posts/gone.md" => entry } })
    SiteSync::Ledger.stubs(:current).returns({})
    written = nil
    SiteSync::Ledger.stubs(:write_manifest!).with { |m| written = m; true }

    job.send(:rebaseline!, { push_add: [], push_delete: [ "posts/gone.md" ], pull_add: [], pull_delete: [] })

    assert_not_includes written.keys, "posts/gone.md"
  end

  # ── The two links together, now closed ───────────────────────────────────

  test "an unresolved conflict stays a push, not a deletion, on the next sync" do
    local = { "posts/ep.md" => entry }
    peer  = {}

    # Unresolved, so it never entered the baseline.
    after = SiteSync::Reconciler.reconcile(baseline: {}, local: local, peer: peer)

    assert_includes after.push, "posts/ep.md", "it should be offered to the peer"
    assert_empty after.pull_delete, "and never deleted from the side that has it"
  end

  # ── The net: nothing is deleted without being asked ──────────────────────

  test "a planned local deletion becomes a confirmable conflict" do
    with_threshold(0) do
    local  = { "posts/ep.md" => entry }
    result = SiteSync::Reconciler.reconcile(baseline: { "posts/ep.md" => entry }, local: local, peer: {})
    assert_includes result.pull_delete, "posts/ep.md", "precondition"

    confirmed = SiteSync::Reconciler.require_delete_confirmation(
      result, baseline: { "posts/ep.md" => entry }, local: local, peer: {}
    )

    assert_empty confirmed.pull_delete, "no deletion is applied unasked"
    assert_equal [ "posts/ep.md" ], confirmed.conflicts.map(&:path)
    assert_equal SiteSync::Reconciler::EDIT_DELETE, confirmed.conflicts.first.type
    assert_equal entry, confirmed.conflicts.first.local, "the view needs this to know it's a deletion"
    assert_nil confirmed.conflicts.first.peer
    end
  end

  test "a planned peer deletion becomes a confirmable conflict too" do
    with_threshold(0) do
    peer   = { "posts/ep.md" => entry }
    result = SiteSync::Reconciler.reconcile(baseline: { "posts/ep.md" => entry }, local: {}, peer: peer)
    assert_includes result.push_delete, "posts/ep.md", "precondition"

    confirmed = SiteSync::Reconciler.require_delete_confirmation(
      result, baseline: { "posts/ep.md" => entry }, local: {}, peer: peer
    )

    assert_empty confirmed.push_delete
    assert_equal SiteSync::Reconciler::DELETE_EDIT, confirmed.conflicts.first.type
    end
  end

  # Confirmation must not turn an ordinary sync into a prompt.
  test "a sync with no deletions is untouched" do
    result = SiteSync::Reconciler.reconcile(
      baseline: {}, local: { "posts/new.md" => entry }, peer: {}
    )
    confirmed = SiteSync::Reconciler.require_delete_confirmation(
      result, baseline: {}, local: { "posts/new.md" => entry }, peer: {}
    )

    assert_equal result.push, confirmed.push
    assert_empty confirmed.conflicts
    assert_same result, confirmed, "no deletions means no new object at all"
  end

  # ── The baseline records what BOTH sides hold ────────────────────────────
  #
  # Nothing was deleted on live — live had never had these files. The baseline
  # claimed otherwise because it was written from the local tree alone.

  test "a local file the peer doesn't have stays out of the baseline" do
    job = SiteSyncTransferJob.new
    job.instance_variable_set(:@kind, :sync)

    SiteSync::Ledger.stubs(:current).returns(
      "posts/shared.md" => entry, "posts/local-only.md" => entry(20)
    )
    SiteSync::Exchange.stubs(:fetch_peer_manifest).returns(
      "files" => { "posts/shared.md" => entry }
    )
    written = nil
    SiteSync::Ledger.stubs(:write_manifest!).with { |m| written = m; true }

    job.send(:write_confirmed_baseline!)

    assert_equal [ "posts/shared.md" ], written.keys,
      "a file the peer never had must not be baselined as synced"
  end

  # And the consequence: it stays a push rather than becoming a deletion.
  test "the unconfirmed file is pushed on the next sync, not deleted" do
    baseline = { "posts/shared.md" => entry }
    local    = { "posts/shared.md" => entry, "posts/local-only.md" => entry(20) }

    result = SiteSync::Reconciler.reconcile(baseline: baseline, local: local, peer: baseline)

    assert_includes result.push, "posts/local-only.md"
    assert_empty result.pull_delete
  end

  # An unreachable peer must not be read as "the peer holds nothing" — that
  # would empty the baseline and make every local file look new.
  test "an unreachable peer leaves the baseline alone" do
    job = SiteSyncTransferJob.new
    job.instance_variable_set(:@kind, :sync)

    SiteSync::Ledger.stubs(:current).returns("posts/a.md" => entry)
    SiteSync::Exchange.stubs(:fetch_peer_manifest).returns(nil)
    SiteSync::Ledger.expects(:write_manifest!).never

    job.send(:write_confirmed_baseline!)
  end

  # ── The confirmation is a threshold, not a permanent gate ────────────────

  test "the threshold governs whether a deletion is confirmed" do
    baseline = { "posts/a.md" => entry, "posts/b.md" => entry }
    local    = baseline

    plan = -> {
      result = SiteSync::Reconciler.reconcile(baseline: baseline, local: local, peer: {})
      SiteSync::Reconciler.require_delete_confirmation(
        result, baseline: baseline, local: local, peer: {}
      )
    }

    with_threshold(0) do
      assert_equal 2, plan.call.conflicts.size, "0 confirms every deletion"
      assert_empty plan.call.pull_delete
    end

    with_threshold(5) do
      assert_empty plan.call.conflicts, "under the threshold, deletions just propagate"
      assert_equal 2, plan.call.pull_delete.size
    end

    with_threshold(1) do
      assert_equal 2, plan.call.conflicts.size, "over the threshold, they're confirmed"
    end

    with_threshold(nil) do
      assert_empty plan.call.conflicts, "nil disables confirmation entirely"
      assert_equal 2, plan.call.pull_delete.size
    end
  end

  def with_threshold(value)
    SiteSync::Reconciler.stubs(:confirm_deletions_over).returns(value)
    yield
  ensure
    SiteSync::Reconciler.unstub(:confirm_deletions_over)
  end

  # The resolution job already knows what to do with these types, which is why
  # they're expressed as conflicts rather than a new concept.
  test "confirming a deletion maps to the right action" do
    job = SiteSyncConflictResolutionJob.new
    conflicts = [
      { "path" => "posts/keep.md",   "type" => "edit_delete" },
      { "path" => "posts/accept.md", "type" => "edit_delete" }
    ]
    plan = job.send(:build_plan,
      { "posts/keep.md" => "local", "posts/accept.md" => "live" }, conflicts)

    assert_equal [ "posts/keep.md" ], plan[:push_add],   "keep mine sends it back to the peer"
    assert_equal [ "posts/accept.md" ], plan[:pull_delete], "keep live accepts the deletion"
  end
end
