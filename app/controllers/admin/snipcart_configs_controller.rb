class Admin::SnipcartConfigsController < Admin::BaseController
  def edit
    @snipcart_config = SnipcartConfig.current
    @test_config = SnipcartConfig.test_config
  end

  def update
    @snipcart_config = SnipcartConfig.current

    # Save test API key to file (all environments)
    api_key_test = params[:snipcart_config][:api_key_test]
    SnipcartConfig.save_test_config({ 'api_key' => api_key_test }) if api_key_test.present?

    # Save live API key to DB — production only
    if params[:snipcart_config][:api_key_live].present?
      if Rails.env.production?
        @snipcart_config.api_key_live = params[:snipcart_config][:api_key_live]
      else
        flash.now[:notice] = "Live key is only saved in production. Test key was saved."
      end
    end

    # Update mode
    @snipcart_config.mode = params[:snipcart_config][:mode] if params[:snipcart_config][:mode].present?

    if @snipcart_config.save
      @snipcart_config.verify!
      flash[:notice] = "Snipcart configuration updated"
      redirect_to edit_admin_snipcart_config_path
    else
      flash.now[:error] = "Failed to save Snipcart configuration"
      @test_config = SnipcartConfig.test_config
      render :edit, status: :unprocessable_entity
    end
  end

  def verify
    @snipcart_config = SnipcartConfig.current
    success = @snipcart_config.verify!

    render json: {
      verified: success,
      verified_at: success ? @snipcart_config.verified_at.iso8601 : nil,
      error: success ? nil : "Could not connect to Snipcart. Check your API key."
    }
  end

  def destroy
    @snipcart_config = SnipcartConfig.current
    @snipcart_config.disconnect!

    flash[:notice] = "Snipcart disconnected"
    redirect_to edit_admin_snipcart_config_path
  end
end
