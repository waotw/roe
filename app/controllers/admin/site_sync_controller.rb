require "tmpdir"

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
    @last_exchange_result  = SiteSync::Exchange.last_exchange_result

    # Cross-side fingerprint comparison — the authoritative "are dev
    # and live actually in sync" signal. Local-only drift (@status,
    # @peer_drift) tells us each side's filesystem-vs-own-ledger
    # state; this tells us whether the two filesystems agree.
    local_fp        = SiteSync::Ledger.fingerprint_for(RoeSitePaths::SITE_PATH) rescue nil
    peer_fp         = @peer_state&.dig(:fingerprint)
    @in_sync_with_peer = local_fp.present? && peer_fp.present? && local_fp == peer_fp

    # When the local ledger was last written = the last successful sync.
    # Persists across cache expiry (unlike the transient transfer status),
    # so the always-on status line can show "last synced …".
    @last_synced_at = begin
      version = SiteSync::Ledger.recorded&.dig("version")
      version.present? ? Time.parse(version.to_s) : nil
    rescue StandardError
      nil
    end

    # Live config for the form (token + peer_url). first_or_create!
    # auto-generates a token on first access, so the form always has
    # something to show.
    @sync_config = SyncConfig.current

    # Site URL from settings - used as default for Peer URL
    @site_url = SiteConfig.site_url

    # In-progress / recently-completed transfer status for the
    # push/pull buttons. nil when nothing has happened recently.
    @transfer_status = Rails.cache.read(SiteSyncTransferJob::STATUS_CACHE_KEY)

    # Static Site Sync section state — only computed when SSG is
    # enabled to keep the page render cheap for everyone else. Diff is
    # only computed when the user has actually configured the sync;
    # otherwise hashing the full static_site/ tree on every admin load
    # would be wasted work.
    if SiteConfig.current("site")&.static_generation_enabled
      @static_site_sync_config          = StaticSiteSyncConfig.current
      @static_site_sync_transfer_status = Rails.cache.read(StaticSiteSyncPushJob::STATUS_CACHE_KEY)
      manifest = StaticSiteSync::PushManifest.new
      @static_site_sync_manifest = manifest
      @static_site_sync_diff = manifest.diff if @static_site_sync_config.configured?
    end
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

    # Clear any cached exchange errors since config changed
    SiteSync::Exchange.clear_exchange_result

    flash[:notice] = "Sync configuration saved."
  rescue => e
    flash[:alert] = "Couldn't save sync config: #{e.message}"
  ensure
    redirect_to admin_site_sync_path
  end

  # Set or clear the backup passphrase that encrypts the live database
  # inside full-site backups. Stored (AR-encrypted) on this install's
  # SyncConfig. The passphrase lives where staging happens — production —
  # so the UI only shows the form there; this action just persists what
  # it's given. A blank value clears it (the DB then drops out of backups;
  # plaintext never ships either way).
  def update_backup_passphrase
    passphrase   = params[:backup_passphrase].to_s
    confirmation = params[:backup_passphrase_confirmation].to_s

    if passphrase.present? && passphrase != confirmation
      flash[:alert] = "Passphrases didn't match. Nothing was changed."
    else
      SyncConfig.current.update!(backup_passphrase: passphrase.presence)
      flash[:notice] =
        if passphrase.present?
          "Backup passphrase saved. Save it somewhere safe — it's the only way to open your encrypted database backups."
        else
          "Backup passphrase cleared. Backups will no longer include the database."
        end
    end
  rescue => e
    flash[:alert] = "Couldn't update backup passphrase: #{e.message}"
  ensure
    redirect_to admin_site_sync_path
  end

  # Decrypt the encrypted database inside a local backup and stream it back
  # as a download. Non-destructive: it never touches the live/dev DB — it
  # decrypts to a temp file, sends it, and the temp dir is cleaned up. For
  # inspecting production data locally or verifying a backup opens.
  def decrypt_backup_database
    name       = params[:name].to_s
    passphrase = params[:passphrase].to_s

    Dir.mktmpdir("roe-decrypt") do |dir|
      dest = File.join(dir, "production.sqlite3")
      SiteSync::BackupManager.restore_db(name, passphrase, dest: dest)
      send_data File.binread(dest),
                filename:    "#{name}-production.sqlite3",
                type:        "application/x-sqlite3",
                disposition: "attachment"
    end
  rescue SiteSync::BackupManager::BackupError => e
    flash[:alert] = e.message
    redirect_to admin_site_sync_path
  end

  # Worst-case DB restore for the LIVE site. Admin uploads an encrypted
  # backup blob + passphrase over HTTPS; we decrypt it and stage it to be
  # swapped in on the next boot (never overwrite the DB the running app
  # holds open). Production-only, and heavily confirmed in the UI.
  def restore_database
    unless Rails.env.production?
      flash[:alert] = "Database restore runs on the live site only. Locally, use “Decrypt database” to download a copy."
      return redirect_to admin_site_sync_path
    end
    unless params[:confirm_understood].present?
      flash[:alert] = "Please confirm you understand this overwrites the live database."
      return redirect_to admin_site_sync_path
    end

    upload = params[:database]
    unless upload.respond_to?(:read)
      flash[:alert] = "Choose an encrypted backup database file to upload."
      return redirect_to admin_site_sync_path
    end

    case SiteSync::PendingRestore.stage_from_upload(upload, params[:passphrase].to_s)
    when :staged
      flash[:notice] = "Database restore staged. Redeploy or restart the live app to apply it — the restored database loads on the next boot. Your current database is kept as a .pre-restore copy."
    when :wrong_passphrase
      flash[:alert] = "That passphrase can't open this backup (or the file is corrupt). Nothing was changed."
    when :not_a_blob
      flash[:alert] = "That file isn't an encrypted Roe database backup. Nothing was changed."
    else
      flash[:alert] = "Couldn't stage the restore. Nothing was changed."
    end
    redirect_to admin_site_sync_path
  rescue => e
    flash[:alert] = "Restore failed: #{e.message}"
    redirect_to admin_site_sync_path
  end

  def regenerate_token
    # Local is source of truth for the shared token. Production receives it
    # from the deploy bootstrap (or a manual paste via update_config) — it
    # should never generate its own. The UI hides the button on production
    # but we reject here too so direct POSTs can't bypass that.
    if Rails.env.production?
      flash[:alert] = "Regenerate is local-only. Use Replace token here to paste a value from local."
    else
      begin
        SyncConfig.current.regenerate_token!
        flash[:notice] = "New token generated. Deploy to push it to the live site."
      rescue => e
        flash[:alert] = "Couldn't regenerate token: #{e.message}"
      end
    end
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

  # Bi-directional sync: reconcile with live and apply the safe changes
  # both ways in one pass. Conflicts stop it (nothing overwritten), so no
  # typed confirmation is needed — both sides are backed up first anyway.
  def sync
    if transfer_in_progress?
      flash[:alert] = "A sync is already running. Wait for it to finish."
      redirect_to admin_site_sync_path
      return
    end

    unless SiteSync::Exchange.can_call_peer?
      flash[:alert] = "Sync requires a peer URL set on this side (dev only)."
      redirect_to admin_site_sync_path
      return
    end

    seed_running_status(:sync)
    SiteSyncTransferJob.perform_later(:sync)
    flash[:notice] = "Syncing with live in the background. Refresh the page to check progress."
    redirect_to admin_site_sync_path
  end

  # Apply the admin's choices for a sync that was blocked by conflicts.
  # Each conflict resolves to "local" (keep mine), "live" (keep theirs),
  # or — the default for a blank/`recent` choice — most-recent by mtime.
  # A top-level `resolve_all` overrides every conflict at once.
  def resolve_conflicts
    if transfer_in_progress?
      flash[:alert] = "Another sync is already running. Wait for it to finish."
      redirect_to admin_site_sync_path
      return
    end

    status = Rails.cache.read(SiteSyncTransferJob::STATUS_CACHE_KEY)
    conflicts = status && status[:state] == :conflicts ? Array(status[:conflicts]) : []
    if conflicts.empty?
      flash[:alert] = "No conflicts to resolve."
      redirect_to admin_site_sync_path
      return
    end

    choices     = params[:resolutions] || {}
    resolve_all = params[:resolve_all].to_s
    resolutions = conflicts.each_with_object({}) do |c, acc|
      path   = c["path"]
      choice = resolve_all.presence || choices[path].to_s
      acc[path] = case choice
      when "local" then "local"
      when "live"  then "live"
      else # "recent" or blank → most-recent by the newer hint (ties → local)
                        c["newer"] == "live" ? "live" : "local"
      end
    end

    seed_running_status(:resolve)
    SiteSyncConflictResolutionJob.perform_later(resolutions, conflicts)
    flash[:notice] = "Applying #{resolutions.size} resolution(s) in the background. Refresh to check progress."
    redirect_to admin_site_sync_path
  end

  # Clear a completed/failed status notice from the UI without
  # waiting for the cache TTL.
  def dismiss_transfer_status
    Rails.cache.delete(SiteSyncTransferJob::STATUS_CACHE_KEY)
    redirect_to admin_site_sync_path
  end

  # JSON status poll for the Stimulus controller on the Site Sync page.
  # Mirrors Admin::UpdatesController#deploy_status — the controller
  # polls every 2 s and updates the live "Currently…" line in place,
  # then reloads when the state leaves :running so the server-rendered
  # completed/failed/reassessment card takes over.
  #
  # `progress` is populated by SiteSyncTransferJob during rsync steps:
  # { completed: 5, total: 12 }. Absent for non-rsync steps, in which
  # case the UI just hides the progress line.
  def transfer_status
    status = Rails.cache.read(SiteSyncTransferJob::STATUS_CACHE_KEY)
    if status.nil?
      render json: { state: nil }
      return
    end

    step_key   = status[:step]
    step_label = step_key.present? ? (SiteSyncTransferJob::STEPS[step_key.to_sym] || step_key.to_s) : nil
    render json: status.merge(step_label: step_label)
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

    unless [ :push, :pull, :sync ].include?(kind)
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
