class Admin::UpdatesController < Admin::BaseController
  def index
    @current_version = UpdateChecker.current_version
    @update_info = UpdateChecker.check_for_updates
  end

  def check
    # Force fresh check by clearing cache
    UpdateChecker.clear_cache
    @update_info = UpdateChecker.check_for_updates
    
    if @update_info
      flash[:notice] = "Update check completed"
    else
      flash[:alert] = "Could not check for updates. Please try again later."
    end
    
    redirect_to admin_updates_path
  end

  def install
    # This would handle the actual installation
    # For now, just show instructions
    @current_version = UpdateChecker.current_version
    @update_info = UpdateChecker.check_for_updates
    
    if @update_info && @update_info[:update_available]
      flash[:notice] = "Update to v#{@update_info[:latest_version]} is available. Please follow the installation instructions below."
    else
      flash[:alert] = "No update available or could not check for updates."
    end
    
    redirect_to admin_updates_path
  end
end
