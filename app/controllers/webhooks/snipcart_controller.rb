class Webhooks::SnipcartController < ApplicationController
  # Snipcart posts every store event to ONE URL (no per-event registration, no
  # management API). Snipcart offers no HMAC, and its requestvalidation callback
  # needs the secret API key — which Roe is dropping (see the Snipcart cleanup
  # cards). So we authenticate the same way as Postmark: an unguessable token in
  # the URL path, matched against SnipcartConfig#webhook_token. The operator
  # pastes the full tokenised URL into Snipcart.
  #
  # We store order.completed and refund.created (as SnipcartOrder), tagged with
  # the payload's mode (Test/Live). Other events are accepted (200) and ignored
  # so Snipcart doesn't retry them.
  skip_before_action :verify_authenticity_token
  skip_before_action :require_authentication

  before_action :verify_webhook_token

  def create
    event   = params[:eventName].to_s
    content = webhook_content
    mode    = webhook_mode

    case event
    when "order.completed"
      SnipcartOrder.record_completed!(content, mode: mode) if content.present?
    when "refund.created"
      SnipcartOrder.record_refund!(content, mode: mode) if content.present?
    end

    head :ok
  rescue => e
    # Log and still 200: a raise here would make Snipcart retry forever. The
    # order can be reconciled from a later event or the Snipcart dashboard.
    Rails.logger.error "Snipcart webhook error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    head :ok
  end

  private

  # Reject anything whose path token doesn't match this install's. A tokenless
  # URL (the legacy route, or a stale paste) fails here too.
  def verify_webhook_token
    expected = SnipcartConfig.current.webhook_token.to_s
    provided = params[:token].to_s

    if expected.blank? || !ActiveSupport::SecurityUtils.secure_compare(provided, expected)
      Rails.logger.warn "Snipcart webhook: bad or missing token"
      head :unauthorized
    end
  end

  # "test" or "live" from the webhook envelope's `mode` field (Snipcart sends
  # "Test"/"Live"). Falls back to the config's current mode if absent.
  def webhook_mode
    raw = (request_body["mode"] || params[:mode]).to_s.downcase
    return "live" if raw == "live"
    return "test" if raw == "test"

    SnipcartConfig.current.mode
  end

  # The order/refund object Snipcart nests under `content` in the webhook body.
  def webhook_content
    request_body["content"] || {}
  end

  def request_body
    @request_body ||= (request.request_parameters.presence || parsed_body) || {}
  end

  def parsed_body
    request.body.rewind
    JSON.parse(request.body.read)
  rescue JSON::ParserError
    {}
  end
end
