class Webhooks::SnipcartController < ApplicationController
  # Snipcart posts every store event to ONE URL (no per-event registration, no
  # management API), and there is no HMAC signature. The only authentication is
  # a per-request token in the X-Snipcart-RequestToken header, which we validate
  # by calling Snipcart back — a request Snipcart itself made will validate; a
  # forged one won't. See the Snipcart integration notes.
  #
  # We store order.completed and refund events (SnipcartOrder); other events are
  # accepted (200) and ignored so Snipcart doesn't retry them.
  skip_before_action :verify_authenticity_token
  skip_before_action :require_authentication

  VALIDATION_URL = "https://app.snipcart.com/api/requestvalidation"

  # Events we act on. Anything else is a no-op 200.
  HANDLED_EVENTS = %w[order.completed refund.created].freeze

  def create
    return head(:unauthorized) unless valid_request_token?

    event   = params[:eventName].to_s
    content = webhook_content

    case event
    when "order.completed"
      SnipcartOrder.record_completed!(content) if content.present?
    when "refund.created"
      SnipcartOrder.record_refund!(content) if content.present?
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

  # The order/refund object Snipcart nests under `content` in the webhook body.
  # Read from the raw parsed JSON, not strong params — the payload is deep and
  # we store it whole rather than permitting each field.
  def webhook_content
    body = request.request_parameters.presence || parsed_body
    (body || {})["content"] || {}
  end

  def parsed_body
    request.body.rewind
    JSON.parse(request.body.read)
  rescue JSON::ParserError
    {}
  end

  # Validate the X-Snipcart-RequestToken by calling Snipcart back. A token from
  # a genuine Snipcart request returns 200; a forged/expired one does not. No
  # token at all is rejected. In development we skip the callout (no real
  # Snipcart requests reach localhost) so the endpoint can be exercised.
  def valid_request_token?
    token = request.headers["X-Snipcart-RequestToken"].to_s
    return false if token.blank?
    return true if Rails.env.development? || Rails.env.test?

    uri = URI("#{VALIDATION_URL}/#{token}")
    res = Net::HTTP.get_response(uri)
    res.is_a?(Net::HTTPSuccess)
  rescue => e
    Rails.logger.warn "Snipcart token validation failed: #{e.message}"
    false
  end
end
