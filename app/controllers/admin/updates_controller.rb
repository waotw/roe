class Admin::UpdatesController < Admin::BaseController
  def index
    @current_version = RoeUpdater::VersionChecker.current_version
    @update_info = RoeUpdater::VersionChecker.check_for_updates
    @last_update = UpdateStatus.order(created_at: :desc).first
    @in_progress = UpdateStatus.where(status: 'in_progress').exists?
  end

  def check
    RoeUpdater::VersionChecker.clear_cache
    @update_info = RoeUpdater::VersionChecker.check_for_updates
    
    if @update_info
      flash[:notice] = "Update check completed"
    else
      flash[:alert] = "Could not check for updates. Please try again later."
    end
    
    redirect_to admin_updates_path
  end

  def start
    version = params[:version]
    
    if UpdateStatus.where(status: 'in_progress').exists?
      flash[:alert] = "An update is already in progress. Please wait for it to complete."
      redirect_to admin_updates_path
      return
    end

    unless license_valid?
      flash[:alert] = "License expired. Please renew to update."
      redirect_to admin_updates_path
      return
    end

    PerformUpdateJob.perform_later(version: version)
    
    flash[:notice] = "Update to v#{version} started. This may take a few minutes."
    redirect_to admin_updates_path
  end

  def status
    update_status = UpdateStatus.order(created_at: :desc).first
    
    render json: {
      status: update_status&.status,
      step: update_status&.current_step,
      progress: update_status&.progress_percent,
      error: update_status&.error_message,
      log: update_status&.log
    }
  end

  def rollback
    if SwitchManager.rollback
      flash[:notice] = "Rollback completed successfully. Please restart the server."
    else
      flash[:alert] = "Rollback failed. Please check the logs and contact support."
    end
    
    redirect_to admin_updates_path
  end

  private

  def license_valid?
    # Placeholder - replace with actual license check
    true
  end
end
