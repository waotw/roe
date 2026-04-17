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

      # Ensure webhook token exists (ADD THIS)
      if @postmark_config.webhook_token.blank?
        @postmark_config.webhook_token = SecureRandom.hex(32)
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

    Rails.logger.info "BEFORE disconnect - server_token present?: #{@postmark_config[:server_token].present?}"

    @postmark_config.disconnect!

    @postmark_config.reload
    Rails.logger.info "AFTER disconnect - server_token present?: #{@postmark_config[:server_token].present?}"
    Rails.logger.info "AFTER disconnect - connected?: #{@postmark_config.connected?}"

    flash[:notice] = "Postmark disconnected"
    redirect_to edit_admin_postmark_config_path
  end

  def regenerate_webhook_token
    @postmark_config = PostmarkConfig.current
    @postmark_config.regenerate_webhook_token!

    flash[:notice] = "Webhook token regenerated. Update the URL in Postmark!"
    redirect_to edit_admin_postmark_config_path
  end
end
