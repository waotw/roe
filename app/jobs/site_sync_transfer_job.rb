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
    pushing_to_live:     "Pushing changed files to live…",
    pushing_to_live_full: "Pushing to live (full tree)…",
    backing_up_local:    "Backing up local…",
    pulling_from_live:   "Pulling changed files from live…",
    pulling_from_live_full: "Pulling from live (full tree)…",
    refreshing_baseline: "Refreshing sync baseline…",
    realigning_mtimes:   "Aligning file timestamps…",
    reconciling_content: "Updating the database to match new files…",
    notifying_peer:      "Notifying peer to refresh its ledger…",
    backing_up_database: "Backing up live database (encrypted)…"
  }.freeze

  # Raised when the three-way reconcile finds files changed on BOTH sides
  # (diverged from the last-synced baseline). The sync stops rather than
  # overwrite either side; the conflicts ride out on the status for the
  # admin to resolve.
  class ConflictsDetected < StandardError
    attr_reader :conflicts

    def initialize(conflicts)
      @conflicts = conflicts
      super("#{conflicts.size} unresolved conflict(s)")
    end
  end

  # Raised when we can't fetch the peer's manifest — without it there's no
  # way to check for conflicts, so we refuse to sync blind.
  class PeerUnreachable < StandardError; end

  def perform(kind)
    kind = kind.to_sym
    raise ArgumentError, "kind must be :push, :pull, :sync or :clone" unless [ :push, :pull, :sync, :clone ].include?(kind)

    @started_at = Time.current
    @kind = kind
    @original_diff = nil  # set during perform_push/pull/sync when computed
    update_step(:starting)

    case kind
    when :push then perform_push
    when :pull then perform_pull
    when :sync then perform_sync
    when :clone then perform_clone
    end

    # /site is now in a known-good state matching the other side.
    # Refresh our ledger + caches so drift indicators clear. Cleared again at
    # the end — realign_phantom_mtimes! below still changes /site, and anything
    # that reads the status in between caches an answer from mid-sync. This
    # early clear is for the paths that never reach the end: a job that fails
    # partway shouldn't leave the banner describing a state from before it ran.
    update_step(:refreshing_baseline)
    SiteSync::Ledger.write_current!
    invalidate_status_caches

    # Reconcile the database against the new on-disk state. rsync only
    # touches files; Post/Page/Product/Medium rows still reference the
    # pre-sync state until something runs ContentSync.sync_all. For
    # push, that something is the peer (called via API); for pull, it's
    # us, in-process. Without this, the receiving side's admin shows
    # ghost rows for deleted files and missing rows for new files
    # until the app restarts.
    update_step(:reconciling_content)
    case @kind
    when :push, :clone then SiteSync::Exchange.reconcile_peer_content!
    when :pull then ContentSync.sync_all
    when :sync
      # Reconcile whichever side(s) actually received writes.
      SiteSync::Exchange.reconcile_peer_content! if @pushed
      ContentSync.sync_all if @pulled
    end

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

    # Phantom-mtime realignment. A peer-side rewrite during reconcile (e.g. a
    # config file re-serialized by ContentSync) can leave a file byte-identical
    # but with a fresher mtime — which the size+mtime drift check reads as a
    # phantom "ledgers diverged" even though the content matches. Stamp the
    # local mtime to the peer's for any such byte-identical file so the two
    # fingerprints end genuinely equal and the sync finishes green. Only the
    # side that can reach the peer runs this (production never initiates).
    if SiteSync::Exchange.can_call_peer?
      update_step(:realigning_mtimes)
      realign_phantom_mtimes!
    end

    # Phase ②: pull a fresh encrypted copy of the live database so the
    # local /site always carries a current, restorable DB blob. Distinct
    # from the content sync above, best-effort, and isolated — the content
    # transfer already succeeded, so a DB-backup hiccup (peer busy, no
    # passphrase set) must never fail the sync. Only the side that can call
    # the peer pulls (production never initiates), so this is a no-op on
    # the live side.
    if SiteSync::Exchange.can_call_peer?
      update_step(:backing_up_database)
      begin
        SiteSync::DatabaseBackup.pull!
      rescue => e
        Rails.logger.warn "[SiteSyncTransferJob #{@kind}] database backup pull failed: #{e.class} #{e.message}"
      end
    end

    write_status(
      state:        :completed,
      kind:         @kind,
      started_at:   @started_at,
      completed_at: Time.current
    )

    # Once more, now that nothing else is going to touch /site.
    #
    # realign_phantom_mtimes! rewrites file mtimes and the ledger with them, but
    # the caches cleared before it were free to be refilled in the meantime —
    # by an admin page render, or the layout banner on any navigation, both of
    # which the "refresh the page to check progress" message invites. A status
    # cached then is computed against the old mtimes while the ledger holds the
    # new ones, so the two disagree and the banner reports drift on a sync that
    # worked. Syncing a second time cleared it, which is what made it look like
    # the first one hadn't taken.
    invalidate_status_caches

    # Tell the peer about our new state right away — without this,
    # both sides have stale state until the next hourly exchange:
    # the peer's banner doesn't know we just pushed, and OUR peer_state
    # cache still has the peer's pre-push fingerprint. Sync (not async)
    # so admin UIs that read peer_state right after a push (like the
    # imports publish panel) see accurate state on the next render
    # without waiting for a queued job. call_peer is best-effort
    # internally — returns nil on failure rather than raising — so
    # this won't flip the just-completed push to "failed."
    SiteSync::Exchange.call_peer if SiteSync::Exchange.can_call_peer?
  rescue ConflictsDetected => e
    # Not a failure — the sync stopped on purpose so nothing is
    # overwritten. Surface the conflicts for the admin to resolve; don't
    # re-raise (retrying blindly won't help).
    Rails.logger.warn "[SiteSyncTransferJob #{kind}] blocked: #{e.message}"
    write_status(
      state:        :conflicts,
      kind:         @kind,
      started_at:   @started_at,
      completed_at: Time.current,
      conflicts:    serialize_conflicts(e.conflicts)
    )
  rescue PeerUnreachable
    write_status(
      state:        :failed,
      kind:         @kind,
      step:         @last_step,
      started_at:   @started_at,
      completed_at: Time.current,
      error:        "Couldn't reach the live site to check for conflicts. Try again when it's reachable."
    )
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
    result = reconcile_or_abort!
    raise ConflictsDetected, result.conflicts if result.any_conflicts?

    # Push only the local-only changes (add/modify) and deletions the peer
    # hasn't touched. Peer-only changes are left alone — a push never
    # clobbers an independent edit on live; that's what pull is for.
    diff = { modified: [], added: result.push, deleted: result.push_delete }
    @original_diff = diff
    if diff_empty?(diff)
      Rails.logger.info "[SiteSyncTransferJob push] nothing safe to push"
      return
    end

    files_to_back_up = diff[:added] + diff[:deleted]
    update_step(:backing_up_live)
    SiteSync.transport.backup_live_to_local!(files: files_to_back_up, on_progress: progress_proc)

    update_step(:pushing_to_live)
    SiteSync.transport.push_local_to_live!(diff: diff, on_progress: progress_proc)
  end

  def perform_pull
    update_step(:computing_diff)
    result = reconcile_or_abort!
    raise ConflictsDetected, result.conflicts if result.any_conflicts?

    # Pull only the peer-only changes; local-only changes stay put.
    diff = { modified: [], added: result.pull, deleted: result.pull_delete }
    @original_diff = diff
    if diff_empty?(diff)
      Rails.logger.info "[SiteSyncTransferJob pull] nothing safe to pull"
      return
    end

    # Local backup is fast (no network), so always do the full
    # snapshot — it's a complete restore point.
    update_step(:backing_up_local)
    SiteSync::BackupManager.create

    update_step(:pulling_from_live)
    SiteSync.transport.pull_live_to_local!(diff: diff, on_progress: progress_proc)
  end

  # Bi-directional: apply the safe changes BOTH ways in one pass. The push
  # set (local-only changes) and pull set (peer-only changes) are disjoint
  # — a path changed on both sides is a conflict and aborts before we get
  # here — so order doesn't matter and nothing is double-handled.
  def perform_sync
    update_step(:computing_diff)
    result = reconcile_or_abort!
    raise ConflictsDetected, result.conflicts if result.any_conflicts?

    push_diff = { modified: [], added: result.push, deleted: result.push_delete }
    pull_diff = { modified: [], added: result.pull, deleted: result.pull_delete }
    @pushed = !diff_empty?(push_diff)
    @pulled = !diff_empty?(pull_diff)
    @original_diff = {
      modified: [],
      added:    push_diff[:added] + pull_diff[:added],
      deleted:  push_diff[:deleted] + pull_diff[:deleted]
    }

    if @pushed
      update_step(:backing_up_live)
      SiteSync.transport.backup_live_to_local!(files: push_diff[:added] + push_diff[:deleted], on_progress: progress_proc)
      update_step(:pushing_to_live)
      SiteSync.transport.push_local_to_live!(diff: push_diff, on_progress: progress_proc)
    end

    if @pulled
      update_step(:backing_up_local)
      SiteSync::BackupManager.create
      update_step(:pulling_from_live)
      SiteSync.transport.pull_live_to_local!(diff: pull_diff, on_progress: progress_proc)
    end
  end

  # First-sync mirror (a "clone"): make the peer an exact copy of this
  # (initiating) side. No reconcile and no conflicts — on a first sync there's
  # no shared ancestor, so the initiator is the source of truth by definition.
  # Pushes every file that differs AND deletes every peer file not present
  # locally, which is what clears a fresh deploy's starter/seed content. The
  # peer content it's about to overwrite/delete is snapshotted first (just that
  # set, not the whole tree) so even a mis-clicked clone is recoverable; the
  # generic perform flow afterwards writes the shared baseline on both sides, so
  # subsequent syncs are clean 3-way merges.
  def perform_clone
    update_step(:computing_diff)
    peer = SiteSync::Exchange.fetch_peer_manifest
    raise PeerUnreachable if peer.nil?

    # Ledger.diff(local, peer): added = local-only, modified = differ,
    # deleted = peer-only. That set IS the mirror — apply it and peer == local.
    diff = SiteSync::Ledger.diff(SiteSync::Ledger.current, peer["files"] || {})
    @original_diff = diff
    @pushed = !diff_empty?(diff)
    return unless @pushed # already identical — nothing to clone

    # Safety net: snapshot only the peer files this mirror will OVERWRITE or
    # DELETE — its own content that isn't coming from local. Added files are new
    # to the peer (nothing to lose) and unchanged files are recoverable from
    # local, so `modified + deleted` is the complete recovery set — no need to
    # pull the whole tree. On a fresh peer that's near-empty; on a retry it
    # shrinks as files converge (already-mirrored files leave the diff).
    update_step(:backing_up_live)
    SiteSync.transport.backup_live_to_local!(files: diff[:modified] + diff[:deleted], on_progress: progress_proc)

    update_step(:pushing_to_live_full)
    SiteSync.transport.push_local_to_live!(diff: diff, on_progress: progress_proc)
  end

  # A peer-side rewrite during reconcile can leave a file byte-identical but
  # with a fresher mtime — a phantom "diverged" under the size+mtime check. For
  # any file whose size matches the peer but mtime differs AND whose content
  # hash matches, stamp the local mtime to the peer's (cheap, no re-transfer) so
  # the fingerprints end equal and the sync finishes green. Refreshes the
  # baseline when anything was realigned. Best-effort: a missing peer manifest
  # or hash just skips the realignment (the file resyncs normally next time).
  # Drop every cached answer about our own sync state. Both are recomputed on
  # demand — the cost is one /site walk on the next page load.
  def invalidate_status_caches
    SiteSync::Checker.clear_cache
    Rails.cache.delete("site_sync:current_fingerprint")
  end

  def realign_phantom_mtimes!
    peer = SiteSync::Exchange.fetch_peer_manifest
    return unless peer
    peer_files = peer["files"] || {}
    local = SiteSync::Ledger.current

    candidates = local.keys.select do |rel|
      l = local[rel]
      p = peer_files[rel]
      p && l["size"] == p["size"] && l["mtime"] != p["mtime"]
    end
    return if candidates.empty?

    peer_hashes = SiteSync::Exchange.fetch_peer_file_hashes(candidates)
    realigned = 0
    candidates.each do |rel|
      full = File.join(RoeSitePaths::SITE_PATH, rel)
      next unless File.file?(full)
      next unless Digest::SHA256.hexdigest(File.read(full)) == peer_hashes[rel]

      t = Time.at(peer_files[rel]["mtime"].to_i)
      File.utime(t, t, full)
      realigned += 1
    end

    if realigned.positive?
      Rails.logger.info "[SiteSyncTransferJob] realigned #{realigned} phantom-mtime file(s)"
      SiteSync::Ledger.write_current!
    end
  rescue => e
    # Never let a realignment hiccup fail a sync that already succeeded.
    Rails.logger.warn "[SiteSyncTransferJob] phantom-mtime realign skipped: #{e.class} #{e.message}"
  end

  # Three-way reconcile against the peer, with edit/edit conflicts confirmed
  # by content hash. Raises PeerUnreachable if we can't fetch the peer's
  # manifest (no manifest → no way to check for conflicts → refuse to sync
  # blind). Returns a confirmed SiteSync::Reconciler::Result.
  def reconcile_or_abort!
    peer = SiteSync::Exchange.fetch_peer_manifest
    raise PeerUnreachable if peer.nil?

    baseline = SiteSync::Ledger.recorded&.dig("files") || {}
    result = SiteSync::Reconciler.reconcile(
      baseline: baseline,
      local:    SiteSync::Ledger.current,
      peer:     peer["files"] || {}
    )

    candidates = SiteSync::Reconciler.hash_candidates(result)
    if candidates.any?
      result = SiteSync::Reconciler.confirm(
        result,
        local_hashes: SiteSync::Reconciler.hashes_for(candidates),
        peer_hashes:  SiteSync::Exchange.fetch_peer_file_hashes(candidates)
      )
    end

    result
  end

  # Flatten conflicts for the status cache: which side is newer (by mtime,
  # UTC seconds) drives the "resolve all by most-recent" default in the UI.
  def serialize_conflicts(conflicts)
    conflicts.map do |c|
      lm = c.local && c.local["mtime"]
      pm = c.peer && c.peer["mtime"]
      newer = if lm && pm
        lm == pm ? "same" : (lm > pm ? "local" : "live")
      elsif lm
        "local"
      elsif pm
        "live"
      else
        "same"
      end
      { "path" => c.path, "type" => c.type.to_s, "local" => c.local, "peer" => c.peer, "newer" => newer }
    end
  end

  # Post-failure check: figure out what actually happened. Returns
  # a hash the UI can render with two layers of detail:
  #
  #   - `in_sync`: aggregate fingerprint comparison. True means
  #     content matches on both sides regardless of the failure
  #     (bookkeeping-only failure — self-heals on next exchange).
  #
  #   - `pending_*` lists: per-file detail. For each file in the
  #     original diff, did it make it to the peer? Requires per-file
  #     state from the peer — only available when we can call out.
  #
  # Best-effort: if the peer ping fails or we can't compute, returns
  # what we have (or nil if even that fails) and the UI falls back to
  # a generic "failed" message.
  def reassess_after_failure
    local_fp = SiteSync::Ledger.fingerprint_for(RoeSitePaths::SITE_PATH)
    peer_fp = nil

    # Get fresh peer state if we can call out (dev only). On prod we
    # can only use the cached peer state, which may be stale.
    if SiteSync::Exchange.can_call_peer?
      peer_payload = SiteSync::Exchange.call_peer
      peer_fp = peer_payload && (peer_payload["fingerprint"] || peer_payload[:fingerprint])
    else
      cached = SiteSync::Exchange.peer_state
      peer_fp = cached && cached[:fingerprint]
    end

    base = {
      local_fingerprint: local_fp,
      peer_fingerprint:  peer_fp,
      in_sync:           local_fp.present? && peer_fp.present? && local_fp == peer_fp
    }

    # If aggregate fingerprints already agree, no need for per-file
    # detail — everything's actually in sync.
    return base if base[:in_sync]

    # Otherwise, drill down: for each file in the original diff, ask
    # the peer "what state is this file in?" and compare to our
    # expected state. This tells the user exactly which files still
    # need to make it through.
    detail = per_file_pending(@kind)
    base.merge(detail || {})
  end

  # Per-file analysis of which files in the original diff are still
  # pending (didn't make it through). Walks the original diff, calls
  # the peer's /api/site_sync/file_states endpoint with those paths,
  # and compares each peer entry to what we expected.
  #
  # Returns nil when we can't reach the peer or have no original diff.
  def per_file_pending(kind)
    return nil unless @original_diff
    return nil unless SiteSync::Exchange.can_call_peer?

    modified = Array(@original_diff[:modified])
    added    = Array(@original_diff[:added])
    deleted  = Array(@original_diff[:deleted])
    all_paths = (modified + added + deleted).uniq
    return nil if all_paths.empty?

    peer_states = SiteSync::Exchange.fetch_peer_file_states(all_paths)
    return nil if peer_states.empty?

    pending_modified = []
    pending_added    = []
    pending_deleted  = []

    case kind
    when :push
      # Push: we expect peer to have local's version of mod+add files,
      # and to NOT have deleted files. Anything else is pending.
      modified.each do |path|
        pending_modified << path unless states_match?(local_file_state(path), peer_states[path])
      end
      added.each do |path|
        pending_added << path unless states_match?(local_file_state(path), peer_states[path])
      end
      deleted.each do |path|
        pending_deleted << path if peer_states[path]
      end
    when :pull
      # Pull: we expect local to have peer's version of mod+add files,
      # and local to NOT have deleted files. Compare local to what
      # peer reports — pending = local doesn't match peer's state.
      modified.each do |path|
        pending_modified << path unless states_match?(local_file_state(path), peer_states[path])
      end
      added.each do |path|
        pending_added << path unless states_match?(local_file_state(path), peer_states[path])
      end
      deleted.each do |path|
        pending_deleted << path if local_file_state(path)
      end
    end

    intended_count = modified.size + added.size + deleted.size
    pending_count  = pending_modified.size + pending_added.size + pending_deleted.size

    {
      intended_count:    intended_count,
      pending_count:     pending_count,
      done_count:        intended_count - pending_count,
      pending_modified:  pending_modified,
      pending_added:     pending_added,
      pending_deleted:   pending_deleted
    }
  rescue => e
    Rails.logger.warn "[SiteSyncTransferJob] per_file_pending failed: #{e.class} #{e.message}"
    nil
  end

  def local_file_state(path)
    full = File.join(RoeSitePaths::SITE_PATH, path)
    return nil unless File.exist?(full)
    stat = File.stat(full)
    { "size" => stat.size, "mtime" => stat.mtime.to_i }
  rescue
    nil
  end

  # Two file states match when both sides have the file with the same
  # size + mtime (rsync's default change-detection signature).
  def states_match?(a, b)
    return false unless a && b
    a["size"] == b["size"] && a["mtime"] == b["mtime"]
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

  # Cross-site diff: compares local filesystem directly to peer's
  # current filesystem. This is the most accurate way to determine
  # what actually needs to be synced, bypassing recorded ledger
  # discrepancies. Falls back to local_diff if peer manifest unavailable.
  def cross_site_diff
    # Try to fetch peer manifest for accurate comparison
    peer_manifest = SiteSync::Exchange.fetch_peer_manifest
    return local_diff unless peer_manifest

    current = SiteSync::Ledger.current
    SiteSync::Ledger.diff(current, peer_manifest["files"])
  rescue => e
    Rails.logger.warn "[SiteSyncTransferJob] cross_site_diff failed: #{e.class} #{e.message}, falling back to local_diff"
    local_diff
  end

  # Peer's drift, as reported via the most recent exchange. Returns
  # nil when:
  #   - we've never spoken to the peer (no cached state)
  #   - peer is older code without drift info
  #   - peer's drift was truncated (we don't have the full list, so
  #     selective sync would miss files — fall back to full pull)
  def peer_diff
    # First try to get accurate diff from peer manifest
    peer_manifest = SiteSync::Exchange.fetch_peer_manifest
    if peer_manifest
      current = SiteSync::Ledger.current
      diff = SiteSync::Ledger.diff(peer_manifest["files"], current)
      return {
        modified: diff[:modified],
        added: diff[:added],
        deleted: diff[:deleted]
      }
    end

    # Fallback to cached drift info
    state = SiteSync::Exchange.peer_state
    drift = state && state[:drift]
    return nil unless drift
    return nil if drift[:truncated]

    {
      modified: Array(drift[:modified]),
      added:    Array(drift[:added]),
      deleted:  Array(drift[:deleted])
    }
  rescue => e
    Rails.logger.warn "[SiteSyncTransferJob] peer_diff failed: #{e.class} #{e.message}"
    nil
  end

  def diff_empty?(diff)
    diff[:modified].empty? && diff[:added].empty? && diff[:deleted].empty?
  end

  # Convenience for "still running, just in a different step." Logs
  # the transition so you can correlate the status panel with what
  # the Rails log shows. Also remembers the most recent step so a
  # failure can report "failed during X".
  #
  # Resets @progress — progress is per-rsync-step. When the step
  # changes (e.g. from :pushing_to_live to :refreshing_baseline), the
  # old file counter is no longer meaningful.
  def update_step(step)
    @last_step = step
    @progress  = nil
    Rails.logger.info "[SiteSyncTransferJob #{@kind}] step: #{step}"
    write_running_status
  end

  # Callable handed to FlyRsync (or any transport) so it can report
  # live file-count progress as rsync churns through the transfer.
  # Each call updates the cache so the next admin poll sees fresh
  # numbers.
  def progress_proc
    @progress_proc ||= ->(completed:, total:) {
      @progress = { completed: completed, total: total }
      write_running_status
    }
  end

  def write_running_status
    payload = {
      state:      :running,
      kind:       @kind,
      step:       @last_step,
      started_at: @started_at
    }
    payload[:progress] = @progress if @progress
    write_status(payload)
  end

  def write_status(data)
    Rails.cache.write(STATUS_CACHE_KEY, data, expires_in: STATUS_TTL)
  end
end
