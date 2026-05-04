# Performs a full local↔live transfer in the background. One job
# class handles both directions — they only differ in (a) which side
# gets backed up first and (b) which way the rsync goes.
#
# When a reliable diff is available (local ledger for push, peer's
# drift for pull) we drive rsync via --files-from so only the
# changed files traverse fly ssh console. This is dramatically
# faster than a full-tree rsync — for a single-file change, sync
# completes in seconds instead of minutes. Falls back to full-tree
# rsync when the diff is unreliable (peer sent truncated drift, or
# none at all).
#
# Status is tracked in a single cache key (only one transfer can run
# at a time anyway) so the admin UI can show in-progress / completed
# / failed without a dedicated table. After a successful transfer
# we also kick off a SiteSyncExchangeJob so the peer's cached view
# of us refreshes immediately rather than waiting for the next
# hourly tick.
class SiteSyncTransferJob < ApplicationJob
  queue_as :default

  STATUS_CACHE_KEY = "site_sync:transfer_status".freeze
  STATUS_TTL       = 1.day

  STEPS = {
    starting:            "Starting…",
    computing_diff:      "Computing what changed…",
    backing_up_live:     "Backing up live (only the files about to change)…",
    backing_up_live_full: "Backing up live (full tree — no diff available)…",
    pushing_to_live:     "Pushing changed files to live…",
    pushing_to_live_full: "Pushing to live (full tree)…",
    backing_up_local:    "Backing up local…",
    pulling_from_live:   "Pulling changed files from live…",
    pulling_from_live_full: "Pulling from live (full tree)…",
    refreshing_baseline: "Refreshing sync baseline…",
    notifying_peer:      "Notifying peer to refresh its ledger…"
  }.freeze

  def perform(kind)
    kind = kind.to_sym
    raise ArgumentError, "kind must be :push or :pull" unless [ :push, :pull ].include?(kind)

    @started_at = Time.current
    @kind = kind
    update_step(:starting)

    case kind
    when :push then perform_push
    when :pull then perform_pull
    end

    # /site is now in a known-good state matching the other side.
    # Refresh our ledger + caches so drift indicators clear.
    update_step(:refreshing_baseline)
    SiteSync::Ledger.write_current!
    SiteSync::Checker.clear_cache
    Rails.cache.delete("site_sync:current_fingerprint")

    # For push: also tell the peer to refresh its ledger. Without
    # this, the peer's drift detection thinks "everything changed"
    # because rsync touched mtimes on every transferred file but
    # the peer's ledger still has the pre-push mtimes. Pull doesn't
    # need this — peer's /site didn't change.
    if @kind == :push
      update_step(:notifying_peer)
      SiteSync::Exchange.refresh_peer_ledger!
    end

    write_status(
      state:        :completed,
      kind:         @kind,
      started_at:   @started_at,
      completed_at: Time.current
    )

    # Tell the peer about our new state right away — without this,
    # the banner on the other side stays stale until the next
    # hourly exchange run.
    SiteSyncExchangeJob.perform_later if SiteSync::Exchange.can_call_peer?
  rescue => e
    Rails.logger.error "[SiteSyncTransferJob #{kind}] #{e.class}: #{e.message}"
    write_status(
      state:        :failed,
      kind:         kind,
      started_at:   @started_at,
      completed_at: Time.current,
      error:        e.message
    )
    raise # let Solid Queue see the failure
  end

  private

  def perform_push
    update_step(:computing_diff)
    diff = local_diff

    if diff && diff_empty?(diff)
      Rails.logger.info "[SiteSyncTransferJob push] no local changes — nothing to push"
      return
    end

    if diff
      # Selective: backup only the files we're about to overwrite/
      # delete on prod, then push only the changed files.
      files_to_back_up = diff[:modified] + diff[:deleted]
      update_step(:backing_up_live)
      SiteSync::FlyRsync.backup_live_to_local!(files: files_to_back_up)

      update_step(:pushing_to_live)
      SiteSync::FlyRsync.push_local_to_live!(diff: diff)
    else
      # Fallback: full-tree backup + push.
      update_step(:backing_up_live_full)
      SiteSync::FlyRsync.backup_live_to_local!

      update_step(:pushing_to_live_full)
      SiteSync::FlyRsync.push_local_to_live!
    end
  end

  def perform_pull
    update_step(:computing_diff)
    diff = peer_diff

    if diff && diff_empty?(diff)
      Rails.logger.info "[SiteSyncTransferJob pull] no remote changes — nothing to pull"
      return
    end

    # Local backup is fast (no network), so always do the full
    # snapshot — it's a complete restore point.
    update_step(:backing_up_local)
    SiteSync::BackupManager.create

    if diff
      update_step(:pulling_from_live)
      SiteSync::FlyRsync.pull_live_to_local!(diff: diff)
    else
      update_step(:pulling_from_live_full)
      SiteSync::FlyRsync.pull_live_to_local!
    end
  end

  # Local diff = changes since this side's recorded ledger. Returns
  # nil if no ledger exists (first sync) so the caller falls back to
  # full-tree push.
  def local_diff
    recorded = SiteSync::Ledger.recorded
    return nil unless recorded

    current = SiteSync::Ledger.current
    SiteSync::Ledger.diff(current, recorded["files"] || {})
  end

  # Peer's drift, as reported via the most recent exchange. Returns
  # nil when:
  #   - we've never spoken to the peer (no cached state)
  #   - peer is older code without drift info
  #   - peer's drift was truncated (we don't have the full list, so
  #     selective sync would miss files — fall back to full pull)
  def peer_diff
    state = SiteSync::Exchange.peer_state
    drift = state && state[:drift]
    return nil unless drift
    return nil if drift[:truncated]

    {
      modified: Array(drift[:modified]),
      added:    Array(drift[:added]),
      deleted:  Array(drift[:deleted])
    }
  end

  def diff_empty?(diff)
    diff[:modified].empty? && diff[:added].empty? && diff[:deleted].empty?
  end

  # Convenience for "still running, just in a different step." Logs
  # the transition so you can correlate the status panel with what
  # the Rails log shows.
  def update_step(step)
    Rails.logger.info "[SiteSyncTransferJob #{@kind}] step: #{step}"
    write_status(
      state:      :running,
      kind:       @kind,
      step:       step,
      started_at: @started_at
    )
  end

  def write_status(data)
    Rails.cache.write(STATUS_CACHE_KEY, data, expires_in: STATUS_TTL)
  end
end
