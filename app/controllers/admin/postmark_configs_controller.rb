class Admin::PostmarkConfigsController < Admin::BaseController
  def edit
    @postmark_config = PostmarkConfig.current
    @test_config = PostmarkConfig.test_config
    @stats = PostmarkService.get_stats if @postmark_config.connected?
  end

  def update
    @postmark_config = PostmarkConfig.current

    test_token = params[:postmark_config][:test_server_token]
    live_token = params[:postmark_config][:server_token]

    # Skip masked placeholders
    test_token = nil if test_token == "••••••••••••••••"
    live_token = nil if live_token == "••••••••••••••••"

    # Save test token to file (all environments)
    if test_token.present?
      PostmarkConfig.save_test_config({ "server_token" => test_token })
    end

    # Save live token to DB — production only
    if live_token.present?
      if Rails.env.production?
        @postmark_config.server_token = live_token
      else
        flash.now[:notice] = "Live token is only saved in production. Test token was saved."
      end
    end

    # Update mode
    @postmark_config.mode = params[:postmark_config][:mode] if params[:postmark_config][:mode].present?

    # Ensure webhook token exists
    @postmark_config.webhook_token ||= SecureRandom.hex(32)

    if @postmark_config.save
      @postmark_config.verify!
      flash[:notice] = "Postmark configuration saved"
      redirect_to edit_admin_postmark_config_path
    else
      flash.now[:error] = "Failed to save Postmark configuration"
      @test_config = PostmarkConfig.test_config
      render :edit, status: :unprocessable_entity
    end
  end

  def verify
    @postmark_config = PostmarkConfig.current
    success = @postmark_config.verify!

    render json: {
      verified: success,
      verified_at: success ? @postmark_config.verified_at.iso8601 : nil,
      error: success ? nil : "Could not connect to Postmark. Check your server token."
    }
  end

  def destroy
    @postmark_config = PostmarkConfig.current
    @postmark_config.disconnect!

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
