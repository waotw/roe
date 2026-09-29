class Admin::OrdersController < Admin::BaseController
  include WebhookUrlHelper

  def index
    @orders = SnipcartOrder.recent
  end

  def show
    @order = SnipcartOrder.find(params[:id])
  end

  private

  # The URL to paste into Snipcart (Store Configurations → Webhooks). Snipcart
  # has no API to register it, so setup is a manual paste — surface the exact
  # URL. Falls back to the path when no public host is resolvable (dev without
  # a tunnel), which is enough to show what to paste once deployed.
  helper_method :snipcart_webhook_url
  def snipcart_webhook_url
    webhook_url("/webhooks/snipcart") || "/webhooks/snipcart"
  end
end
