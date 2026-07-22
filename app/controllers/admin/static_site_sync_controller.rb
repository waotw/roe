class Admin::StaticSiteSyncController < Admin::BaseController
  # Save SFTP connection details. Password / SSH key are encrypted by
  # the model — they don't appear in any plaintext config. Sets
  # last_verification_error to nil so the UI stops showing stale errors
  # after the user edits the form.
  def update_config
    config = StaticSiteSyncConfig.current

    attrs = params.require(:static_site_sync_config).permit(
      :protocol, :host, :port, :username, :auth_mode, :password, :ssh_private_key, :remote_path, :verify_tls, :ssh_key_passphrase
    )

    # Empty password / key in the form means "don't change" — let the
    # existing encrypted value stand. The admin form always submits the
    # field, so an empty string from a user who left it blank is benign;
    # one from a user who actually cleared the field is rare and
    # recoverable by editing again.
    attrs.delete(:password) if attrs[:password].blank?
    attrs.delete(:ssh_private_key) if attrs[:ssh_private_key].blank?
    attrs.delete(:ssh_key_passphrase) if attrs[:ssh_key_passphrase].blank?

    # The form no longer offers an auth-method choice — the protocol decides:
    # SFTP always uses the SSH key, FTPS always uses the password. Derive
    # auth_mode so the pusher picks the right path regardless of what was
    # previously stored.
    attrs[:auth_mode] = "ssh_key"  if attrs[:protocol] == "sftp"
    attrs[:auth_mode] = "password" if attrs[:protocol] == "ftps"

    config.assign_attributes(attrs)
    config.last_verification_error = nil

    if config.save
      flash[:notice] = "Static Site Sync settings saved."
      # When the user picks ZIP and submits, the button reads
      # "Download ZIP" — match that by routing them straight to the
      # download endpoint after save. Save + download in one click.
      if config.protocol_zip?
        redirect_to admin_download_static_site_zip_path and return
      end
    else
      flash[:alert] = "Could not save: #{config.errors.full_messages.to_sentence}"
    end
    redirect_to admin_site_sync_path(tab: "static-sync")
  end

  # Open a session, stat the remote path, close. Records the result on
  # the config so the UI can show "Connected ✓" or the error.
  def test_connection
    config = StaticSiteSyncConfig.current
    if config.protocol_zip?
      flash[:notice] = "ZIP downloads have nothing to test — the archive is generated locally."
      redirect_to admin_site_sync_path(tab: "static-sync") and return
    end
    unless config.configured?
      flash[:alert] = "Fill in host, username, credentials, and remote path before testing."
      redirect_to admin_site_sync_path(tab: "static-sync") and return
    end

    pusher = StaticSiteSync::Pusher.for(config: config)
    pusher.test_connection
    config.update!(last_verified_at: Time.current, last_verification_error: nil)
    flash[:notice] = "Connection succeeded."
  rescue StaticSiteSync::Pusher::ConnectionError => e
    config.update!(last_verification_error: e.message)
    flash[:alert] = "Connection failed: #{e.message}"
  ensure
    redirect_to admin_site_sync_path(tab: "static-sync")
  end

  # Kick off the push job. Same single-flight pattern as
  # SiteSyncTransferJob — if another transfer is in flight, decline.
  def push
    config = StaticSiteSyncConfig.current
    if config.protocol_zip?
      flash[:alert] = "ZIP downloads use the Download button, not Push."
      redirect_to admin_site_sync_path(tab: "static-sync") and return
    end
    if transfer_in_progress?
      flash[:alert] = "A push is already running. Wait for it to finish."
      redirect_to admin_site_sync_path(tab: "static-sync") and return
    end
    unless config.configured?
      flash[:alert] = "Configure the connection before pushing."
      redirect_to admin_site_sync_path(tab: "static-sync") and return
    end

    full = params[:full].present?
    seed_running_status
    StaticSiteSyncPushJob.perform_later(full: full)
    flash[:notice] = if full
      "Full re-sync started — re-uploading everything and pruning files removed locally. Refresh to check progress."
    else
      "Push started in the background. Refresh to check progress."
    end
    redirect_to admin_site_sync_path(tab: "static-sync")
  end

  # Generate and stream a ZIP of /static_site to the browser. The ZIP
  # protocol is the manual / universal escape hatch — works for any
  # host that takes file uploads, including drag-drop-zip targets
  # (Netlify Drop) and anywhere SFTP/FTPS aren't options.
  #
  # Synchronous: no background job, no progress UI. For small-to-mid
  # sites the build takes a couple seconds and the browser holds the
  # connection open until the tempfile is ready. Marks the push
  # manifest on completion so drift detection resets the same way an
  # SFTP push does — we trust the user to actually upload it.
  def download_zip
    config = StaticSiteSyncConfig.current
    unless config.protocol_zip?
      flash[:alert] = "Download is only available when the deploy protocol is set to ZIP."
      redirect_to admin_site_sync_path(tab: "static-sync") and return
    end

    builder  = StaticSiteSync::ZipBuilder.new
    tempfile = builder.build_tempfile
    filename = "static_site_#{Time.current.strftime('%Y%m%d_%H%M%S')}.zip"

    StaticSiteSync::PushManifest.new.record_full_snapshot!
    config.update!(last_pushed_at: Time.current)

    send_file tempfile.path,
              filename: filename,
              type: "application/zip",
              disposition: "attachment"
  end

  # JSON status poll for the Stimulus controller. Mirrors
  # Admin::SiteSyncController#transfer_status exactly so the front-end
  # pattern is reusable: same response shape, same step_label mapping.
  def transfer_status
    status = Rails.cache.read(StaticSiteSyncPushJob::STATUS_CACHE_KEY)
    if status.nil?
      render json: { state: nil }
      return
    end

    step_key   = status[:step]
    step_label = step_key.present? ? (StaticSiteSyncPushJob::STEPS[step_key.to_sym] || step_key.to_s) : nil
    render json: status.merge(step_label: step_label)
  end

  def dismiss_transfer_status
    Rails.cache.delete(StaticSiteSyncPushJob::STATUS_CACHE_KEY)
    redirect_to admin_site_sync_path(tab: "static-sync")
  end

  private

  def transfer_in_progress?
    status = Rails.cache.read(StaticSiteSyncPushJob::STATUS_CACHE_KEY)
    status && status[:state] == :running
  end

  # Pre-seed the status cache so the UI shows the running panel the
  # instant the redirect lands, before the worker actually picks up
  # the job. The worker then overwrites with real step info.
  def seed_running_status
    Rails.cache.write(
      StaticSiteSyncPushJob::STATUS_CACHE_KEY,
      { state: :running, kind: :push, step: :starting, started_at: Time.current },
      expires_in: StaticSiteSyncPushJob::STATUS_TTL
    )
  end
end
