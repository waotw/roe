class Admin::SnipcartConfigsController < Admin::BaseController
  before_action :require_production_features

  def edit
    @snipcart_config = SnipcartConfig.current
  end

  def update
    @snipcart_config = SnipcartConfig.current

    # Get the values from params
    api_key_test = params[:snipcart_config][:api_key_test]
    api_key_live = params[:snipcart_config][:api_key_live]
    snippet = params[:snipcart_config][:snippet]

    # Build update params
    update_params = {}
    update_params[:api_key_test] = api_key_test if api_key_test.present?
    update_params[:api_key_live] = api_key_live if api_key_live.present?
    update_params[:snippet] = snippet if snippet.present?
    update_params[:mode] = params[:snipcart_config][:mode] if params[:snipcart_config][:mode].present?

    if update_params.any? && @snipcart_config.update(update_params)
      flash[:notice] = "Snipcart configuration updated successfully"
      redirect_to edit_admin_snipcart_config_path
    else
      flash.now[:error] = "Please enter at least a test API key"
      render :edit
    end
  end

  def destroy
    @snipcart_config = SnipcartConfig.current
    @snipcart_config.disconnect!

    flash[:notice] = "Snipcart disconnected successfully"
    redirect_to edit_admin_snipcart_config_path
  end
end
