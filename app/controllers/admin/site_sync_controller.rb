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
