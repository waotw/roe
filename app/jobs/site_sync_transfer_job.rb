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
    @original_diff = nil  # set during perform_push/perform_pull when computed
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

    # Tell the peer to refresh its ledger too — for both push and
    # pull. The motivations differ slightly:
    #   - Push: peer's /site changed (we wrote to it). Without a
    #     refresh, peer's drift would scream "everything changed!"
    #     because rsync touched mtimes on every transferred file
    #     but peer's ledger still has the pre-push mtimes.
    #   - Pull: peer's /site didn't change, but our pull means we've
    #     adopted peer's current state as the truth. Resetting
    #     peer's baseline makes its drift signal clear too — both
    #     sides agree they're in sync now.
    update_step(:notifying_peer)
    SiteSync::Exchange.refresh_peer_ledger!

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

    # Re-assess: a partial push/pull might have actually completed in
    # content terms (e.g. failure was in the bookkeeping step, not the
    # rsync). Compare current local fingerprint to peer's to give the
    # UI an accurate picture instead of a generic "failed."
    reassessment = reassess_after_failure rescue nil

    write_status(
      state:         :failed,
      kind:          kind,
      step:          @last_step,
      started_at:    @started_at,
      completed_at:  Time.current,
      error:         e.message,
      original_diff: serialize_diff(@original_diff),
      reassessment:  reassessment
    )
    raise # let Solid Queue see the failure
  end

  private

  def perform_push
    update_step(:computing_diff)
    diff = local_diff
    @original_diff = diff  # preserve for failure reassessment

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
    @original_diff = diff

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

  # Quick post-failure check: do both sides actually agree on
  # content, despite the failure? If yes, the transfer effectively
  # succeeded — only bookkeeping failed (notifying_peer, write_current!,
  # etc.). If no, there's real pending work.
  #
  # Returns a small hash the UI can render. Best-effort: if the peer
  # ping fails or we can't compute fingerprints, returns nil and the
  # UI falls back to a generic "failed" message.
  def reassess_after_failure
    local_fp = SiteSync::Ledger.fingerprint_for(RoeSitePaths::SITE_PATH)
    peer_fp = nil

    # Get fresh peer state if we can call out (dev only). On prod
    # we can only use the cached peer state, which may be stale.
    if SiteSync::Exchange.can_call_peer?
      peer_payload = SiteSync::Exchange.call_peer
      peer_fp = peer_payload && (peer_payload['fingerprint'] || peer_payload[:fingerprint])
    else
      cached = SiteSync::Exchange.peer_state
      peer_fp = cached && cached[:fingerprint]
    end

    {
      local_fingerprint: local_fp,
      peer_fingerprint:  peer_fp,
      in_sync:           local_fp.present? && peer_fp.present? && local_fp == peer_fp
    }
  end

  # Diffs are symbol-keyed in memory but solid_cache serializes them
  # as a Marshal blob (which preserves symbols). For safety in case
  # the cache adapter changes, normalize to plain string-keyed data
  # that survives any serialization.
  def serialize_diff(diff)
    return nil unless diff
    {
      "modified" => Array(diff[:modified]),
      "added"    => Array(diff[:added]),
      "deleted"  => Array(diff[:deleted])
    }
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
  # the Rails log shows. Also remembers the most recent step so a
  # failure can report "failed during X".
  def update_step(step)
    @last_step = step
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
