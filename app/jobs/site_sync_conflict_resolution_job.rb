# Applies the admin's conflict resolutions after a sync was blocked by
# SiteSyncTransferJob. Each resolution is "local" (keep mine) or "live"
# (keep theirs); combined with the conflict's type that dictates a
# targeted per-file action — push it, delete it on live, pull it, or
# delete it locally — so both sides end up agreeing on that path. Reuses
# the same transport + backups the transfer job does.
class SiteSyncConflictResolutionJob < ApplicationJob
  queue_as :default

  # resolutions: { "path" => "local" | "live" }
  # conflicts:   the serialized conflicts from the blocked status (each has
  #              "path" and "type"), so we know the right action per path.
  def perform(resolutions, conflicts)
    started_at = Time.current
    resolutions = resolutions.to_h
    plan = build_plan(resolutions, conflicts)

    write_status(state: :running, step_label: "Resolving #{resolutions.size} conflict(s)…", started_at: started_at)

    pushed = plan[:push_add].any? || plan[:push_delete].any?
    pulled = plan[:pull_add].any? || plan[:pull_delete].any?

    # Keep-mine files flow local → live.
    if pushed
      SiteSync.transport.backup_live_to_local!(files: plan[:push_add] + plan[:push_delete])
      SiteSync.transport.push_local_to_live!(diff: { modified: [], added: plan[:push_add], deleted: plan[:push_delete] })
    end

    # Keep-live files flow live → local.
    if pulled
      @local_snapshot = SiteSync::BackupManager.create
      SiteSync.transport.pull_live_to_local!(diff: { modified: [], added: plan[:pull_add], deleted: plan[:pull_delete] })
    end

    # Re-baseline only what was actually settled.
    #
    # This used to write the whole local tree as the new baseline, whatever the
    # admin had resolved. A conflict left unresolved is skipped by build_plan —
    # correctly — but it was still recorded as "last known synced". On the next
    # sync that path is in the baseline, unchanged locally and absent on the
    # peer, which the reconciler reads as "the peer deleted it" and applies
    # locally. No conflict, no prompt: the file just goes.
    #
    # That deleted 9 podcast episodes and 23 audio files from a working local
    # site on 2026-08-26. An unresolved path must stay out of the baseline so
    # it keeps showing up as a conflict until someone decides.
    rebaseline!(plan)
    invalidate_status_caches

    ContentSync.sync_all if pulled
    SiteSync::Exchange.reconcile_peer_content! if pushed
    SiteSync::Exchange.refresh_peer_ledger!

    # Again, now nothing else will touch /site. ContentSync above can rewrite a
    # file on its way through (a config re-serialized, say), and anything that
    # read our status in between — an admin page render, the layout banner —
    # cached an answer computed before that happened. Left alone, the banner
    # reports drift on a resolve that worked.
    invalidate_status_caches

    SiteSync::History.record!(
      kind:     :resolve,
      outcome:  :completed,
      to_live:  { added: plan[:push_add], deleted: plan[:push_delete] },
      to_local: { added: plan[:pull_add], deleted: plan[:pull_delete] },
      snapshot: @local_snapshot,
      at:       started_at
    )

    write_status(state: :completed, kind: :resolve, started_at: started_at, completed_at: Time.current)
    SiteSync::Exchange.call_peer if SiteSync::Exchange.can_call_peer?
  rescue => e
    Rails.logger.error "[SiteSyncConflictResolutionJob] #{e.class}: #{e.message}"
    write_status(state: :failed, kind: :resolve, error: e.message, completed_at: Time.current)
    raise
  end

  private

  # The baseline means "the state both sides are known to hold". Only paths
  # this run actually transferred or deleted qualify; everything else keeps
  # whatever the last real sync recorded — including being absent, which is
  # what keeps a local-only file safely on the push side of the next reconcile.
  def rebaseline!(plan)
    recorded = SiteSync::Ledger.recorded&.dig("files") || {}
    current  = SiteSync::Ledger.current
    settled  = plan.values.flatten.uniq

    baseline = recorded.dup
    settled.each do |path|
      if current.key?(path)
        baseline[path] = current[path]
      else
        baseline.delete(path)
      end
    end

    Rails.logger.info "[SiteSyncConflictResolutionJob] re-baselined #{settled.size} settled path(s); " \
                      "#{(recorded.keys | current.keys).size - baseline.size} left out of the baseline"
    SiteSync::Ledger.write_manifest!(baseline)
  end

  # Drop every cached answer about our own sync state. Both are recomputed on
  # demand — the cost is one /site walk on the next page load.
  def invalidate_status_caches
    SiteSync::Checker.clear_cache
    Rails.cache.delete("site_sync:current_fingerprint")
  end

  # Map each resolved conflict to a concrete action. `local` wins push
  # local's version (or propagate its delete); `live` wins take the peer's.
  def build_plan(resolutions, conflicts)
    plan = { push_add: [], push_delete: [], pull_add: [], pull_delete: [] }

    Array(conflicts).each do |c|
      path   = c["path"] || c[:path]
      type   = (c["type"] || c[:type]).to_s
      winner = resolutions[path]
      next unless winner

      case [ type, winner ]
      when %w[edit_edit local], %w[edit_delete local]
        plan[:push_add] << path       # send local's version (edit_delete → recreate on live)
      when %w[delete_edit local]
        plan[:push_delete] << path    # propagate local's delete to live
      when %w[edit_edit live], %w[delete_edit live]
        plan[:pull_add] << path       # take live's version (delete_edit → recreate locally)
      when %w[edit_delete live]
        plan[:pull_delete] << path    # accept live's delete locally
      end
    end

    plan
  end

  def write_status(attrs)
    Rails.cache.write(SiteSyncTransferJob::STATUS_CACHE_KEY, attrs, expires_in: SiteSyncTransferJob::STATUS_TTL)
  end
end
