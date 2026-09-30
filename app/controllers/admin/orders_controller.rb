class Admin::OrdersController < Admin::BaseController
  include WebhookUrlHelper

  # The Orders page reflects the CURRENT Snipcart mode: in test mode it shows
  # test orders (so a test purchase visibly confirms the webhook works), in live
  # mode it shows only real orders. The mode toggle lives on the Snipcart
  # integration settings page.
  def index
    @mode = SnipcartConfig.current.mode
    @orders = SnipcartOrder.for_mode(@mode).recent
  end

  def show
    @order = SnipcartOrder.find(params[:id])
  end
end
