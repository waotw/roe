class Admin::SiteSyncController < Admin::BaseController
  LAST_RESTORE_CACHE_KEY = "site_sync:last_restore".freeze
  LAST_RESTORE_TTL       = 7.days  # outlives the user's work session;
                                   # the panel itself only renders if
                                   # the restore was within the last
                                   # hour (see view).

  def index
    @status             = SiteSync::Checker.status
    @local_backups      = SiteSync::BackupManager.list
    @production_backups = SiteSync::BackupManager.list_production
    @last_restore       = Rails.cache.read(LAST_RESTORE_CACHE_KEY)

    # If the backup the panel references has since been deleted
    # (manually or by retention pruning), hide the panel — its
    # message would point at a name that no longer exists. Also
    # clear the stale cache entry so it doesn't reappear.
    if @last_restore && @local_backups.none? { |b| b[:name] == @last_restore[:name] }
      Rails.cache.delete(LAST_RESTORE_CACHE_KEY)
      @last_restore = nil
    end

    # Peer state for the cross-env section. refresh_if_stale will
    # enqueue a background ping if the cached value is older than
    # the threshold; the current request just gets whatever's
    # already cached, so the page doesn't block on the HTTP call.
    @peer_state            = SiteSync::Exchange.refresh_if_stale
    @peer_drift            = SiteSync::Exchange.peer_has_drift?
    @peer_call_configured  = SiteSync::Exchange.can_call_peer?
    @peer_url              = SiteSync::Exchange.peer_url
    @peer_reachable        = SiteSync::Exchange.peer_reachable?
    @deploy_target_label   = SiteSync.deploy_target_label

    # Live config for the form (token + peer_url). first_or_create!
    # auto-generates a token on first access, so the form always has
    # something to show.
    @sync_config = SyncConfig.current

    # In-progress / recently-completed transfer status for the
    # push/pull buttons. nil when nothing has happened recently.
    @transfer_status = Rails.cache.read(SiteSyncTransferJob::STATUS_CACHE_KEY)
  end

  def mark_synced
    SiteSync::Ledger.write_current!
    SiteSync::Checker.clear_cache
    flash[:notice] = "Sync baseline updated. /site is now the recorded state."
  rescue => e
    flash[:alert] = "Failed to update baseline: #{e.message}"
  ensure
    redirect_to admin_site_sync_path
  end

  def create_backup
    path = SiteSync::BackupManager.create
    Rails.cache.delete("site_sync:current_fingerprint")
    flash[:notice] = "Backup created: #{File.basename(path)}"
  rescue SiteSync::BackupManager::BackupError => e
    flash[:alert] = e.message
  ensure
    redirect_to admin_site_sync_path
  end

  # Update peer URL + token from the form. Token is optional —
  # if blank, leaves the existing one untouched (so the user can
  # save a peer_url change without re-typing the token).
  def update_config
    config = SyncConfig.current
    config.peer_url = params[:peer_url].to_s.strip.presence
    config.token = params[:token] if params[:token].present?
    config.save!

    flash[:notice] = "Sync configuration saved."
  rescue => e
    flash[:alert] = "Couldn't save sync config: #{e.message}"
  ensure
    redirect_to admin_site_sync_path
  end

  def regenerate_token
    SyncConfig.current.regenerate_token!
    flash[:notice] = "New token generated. Set the same token on the other side."
  rescue => e
    flash[:alert] = "Couldn't regenerate token: #{e.message}"
  ensure
    redirect_to admin_site_sync_path
  end

  # Push local /site to live via fly-rsync, in the background. The
  # type-to-confirm gate is required because the underlying rsync
  # uses --delete: any file present on live but missing locally will
  # be removed. Live is snapshotted first so the operation is
  # reversible from the production-backup list.
  def push_to_live
    if transfer_in_progress?
      flash[:alert] = "Another sync is already running. Wait for it to finish."
      redirect_to admin_site_sync_path
      return
    end

    unless SiteSync::Exchange.can_call_peer?
      flash[:alert] = "Push requires a peer URL set on this side (dev only)."
      redirect_to admin_site_sync_path
      return
    end

    unless params[:confirm].to_s.strip == "LIVE"
      flash[:alert] = "Push aborted — the confirmation didn't match \"LIVE\"."
      redirect_to admin_site_sync_path
      return
    end

    seed_running_status(:push)
    SiteSyncTransferJob.perform_later(:push)
    flash[:notice] = "Pushing to live in the background. This usually takes a few minutes — refresh the page to check progress."
    redirect_to admin_site_sync_path
  end

  # Pull live's /site over local. Local is snapshotted first
  # (regular site_backups/local/ entry) so the pull is reversible
  # from the local backup list — no typed confirmation needed
  # since we can always restore.
  def pull_from_live
    if transfer_in_progress?
      flash[:alert] = "Another sync is already running. Wait for it to finish."
      redirect_to admin_site_sync_path
      return
    end

    unless SiteSync::Exchange.can_call_peer?
      flash[:alert] = "Pull requires a peer URL set on this side (dev only)."
      redirect_to admin_site_sync_path
      return
    end

    seed_running_status(:pull)
    SiteSyncTransferJob.perform_later(:pull)
    flash[:notice] = "Pulling from live in the background. Refresh the page to check progress."
    redirect_to admin_site_sync_path
  end

  # Clear a completed/failed status notice from the UI without
  # waiting for the cache TTL.
  def dismiss_transfer_status
    Rails.cache.delete(SiteSyncTransferJob::STATUS_CACHE_KEY)
    redirect_to admin_site_sync_path
  end

  # Re-run a previously-failed transfer. Uses the kind from the
  # last status payload (push or pull). The new job will compute
  # a fresh diff — if some files made it through last time, that
  # diff will be smaller and the retry only does the remaining
  # work. If the previous failure was actually bookkeeping-only
  # (content matches), the new diff is empty and the job no-ops.
  def retry_transfer
    last = Rails.cache.read(SiteSyncTransferJob::STATUS_CACHE_KEY)
    kind = last && last[:kind]

    unless [ :push, :pull ].include?(kind)
      flash[:alert] = "Can't retry — no recent transfer status to retry from."
      redirect_to admin_site_sync_path
      return
    end

    if transfer_in_progress?
      flash[:alert] = "Another sync is already running. Wait for it to finish."
      redirect_to admin_site_sync_path
      return
    end

    seed_running_status(kind)
    SiteSyncTransferJob.perform_later(kind)
    flash[:notice] = "Retrying #{kind} in the background. The job will only re-do what's still pending."
    redirect_to admin_site_sync_path
  end

  # Force a synchronous exchange call. Useful for testing — without
  # this you'd have to wait for the hourly job (or 60s on-render
  # debounce) to see fresh peer state. Synchronous so the user gets
  # an immediate result, with a brief HTTP timeout to keep the
  # request from hanging if the peer is unreachable.
  def refresh_exchange
    if !SiteSync::Exchange.can_call_peer?
      flash[:alert] = "This side doesn't initiate exchanges (no peer URL configured)."
    else
      result = SiteSync::Exchange.call_peer
      if result
        flash[:notice] = "Exchange complete — peer state refreshed."
      else
        flash[:alert] = "Exchange failed. Check Rails logs for details (likely token mismatch, wrong peer URL, or peer unreachable)."
      end
    end
  rescue => e
    flash[:alert] = "Exchange error: #{e.message}"
  ensure
    redirect_to admin_site_sync_path
  end

  def restore_backup
    result = SiteSync::BackupManager.restore(params[:name])
    SiteSync::Checker.clear_cache
    # Bust the fingerprint cache so the just-restored backup shows
    # as "currently active" immediately on the next render.
    Rails.cache.delete("site_sync:current_fingerprint")

    Rails.cache.write(
      LAST_RESTORE_CACHE_KEY,
      {
        name:        params[:name],
        file_count:  result[:file_count],
        restored_at: result[:restored_at]
      },
      expires_in: LAST_RESTORE_TTL
    )

    flash[:notice] = "Restored from #{params[:name]} (#{result[:file_count]} files)."
  rescue SiteSync::BackupManager::BackupError => e
    flash[:alert] = e.message
  ensure
    redirect_to admin_site_sync_path
  end

  private

  def transfer_in_progress?
    Rails.cache.read(SiteSyncTransferJob::STATUS_CACHE_KEY)&.dig(:state) == :running
  end

  # Write the running status synchronously before enqueueing so
  # the UI shows "running" on the immediate redirect, even if the
  # Solid Queue worker hasn't picked the job up yet.
  def seed_running_status(kind)
    Rails.cache.write(
      SiteSyncTransferJob::STATUS_CACHE_KEY,
      { state: :running, kind: kind, started_at: Time.current },
      expires_in: SiteSyncTransferJob::STATUS_TTL
    )
  end
end
