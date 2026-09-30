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

  private

  # The URL to paste into Snipcart (Store Configurations → Webhooks). Snipcart
  # has no API to register it, so setup is a manual paste — surface the exact
  # URL, including the secret path token that authenticates the webhook. Falls
  # back to a relative path when no public host is resolvable (dev without a
  # tunnel), which still shows the token so it's clear what to paste once live.
  helper_method :snipcart_webhook_url
  def snipcart_webhook_url
    token = SnipcartConfig.current.ensure_webhook_token!
    webhook_url("/webhooks/snipcart/#{token}") || "/webhooks/snipcart/#{token}"
  end
end
