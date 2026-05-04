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

    # Live config for the form (token + peer_url). first_or_create!
    # auto-generates a token on first access, so the form always has
    # something to show.
    @sync_config = SyncConfig.current
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
end
