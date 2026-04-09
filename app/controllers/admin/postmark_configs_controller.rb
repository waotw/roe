class Admin::PostmarkConfigsController < Admin::BaseController
  def edit
    @postmark_config = PostmarkConfig.current
    @stats = PostmarkService.get_stats if @postmark_config.connected?
  end

  def update
    @postmark_config = PostmarkConfig.current

    # Get the value from params
    server_token = params[:postmark_config][:server_token]

    # Skip if it's the masked placeholder
    server_token = nil if server_token == '••••••••••••••••'

    # Test credentials if provided
    if server_token.present?
      test_result = PostmarkService.test_connection(server_token)

      unless test_result[:success]
        flash[:error] = "Failed to connect to Postmark: #{test_result[:error]}"
        redirect_to edit_admin_postmark_config_path and return
      end
    end

    # Update only if value is provided
    if server_token.present?
      @postmark_config.server_token = server_token
    end

    if @postmark_config.save
      flash[:notice] = "Postmark configuration saved successfully"
      redirect_to edit_admin_postmark_config_path
    else
      flash.now[:error] = "Failed to save Postmark configuration"
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @postmark_config = PostmarkConfig.current
    @postmark_config.disconnect!

    flash[:notice] = "Postmark disconnected"
    redirect_to edit_admin_postmark_config_path
  end
end
