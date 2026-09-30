# Snipcart webhook auth + order mode.
#
# Snipcart offers no HMAC and its requestvalidation callback needs the secret
# API key (which Roe is dropping — see the Snipcart cleanup cards), so we secure
# the webhook the same way as Postmark: an unguessable token in the URL path.
# The operator pastes the full tokenised URL into Snipcart; Roe checks the token.
#
# `mode` records whether an order arrived in Test or Live mode (from the webhook
# payload's `mode` field) so the Orders page can show test orders only while
# Roe/Snipcart is in test mode, and real orders in live mode.
class AddSnipcartWebhookTokenAndOrderMode < ActiveRecord::Migration[8.1]
  def change
    add_column :snipcart_configs, :webhook_token, :string
    add_column :snipcart_orders, :mode, :integer, default: 0, null: false
    add_index  :snipcart_orders, :mode
  end
end
