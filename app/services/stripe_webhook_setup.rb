# frozen_string_literal: true

# Creates (or refreshes) the Stripe webhook endpoint Roe needs, and captures
# its signing secret — the one Stripe credential that otherwise has to be
# hand-copied from the dashboard after creating the endpoint by hand.
#
# Why this exists: Roe's webhook receiver (WebhooksController#stripe) verifies
# every payload with a signing secret. Setting that up manually is the fiddly
# step — create an endpoint aimed at Roe's URL, enable exactly the events Roe
# handles, then copy the `whsec_…` back into Roe. This does all three from the
# secret key the user already pastes.
#
# The hard constraint that shapes everything here: Stripe returns a webhook
# endpoint's `secret` **only at creation** (confirmed against the API ref —
# list/retrieve omit it). So Roe cannot read back the secret of an endpoint
# that already exists. To guarantee it holds a working secret, an existing
# endpoint at Roe's exact URL is deleted and recreated rather than reused —
# safe, because that URL is Roe's own receiver and nothing else points at it.
# (This is the one place the Postmark "reuse existing" rule is inverted, and
# for a concrete reason: Postmark hands its server token back on read; Stripe
# never hands the webhook secret back.)
#
# Never persists anything itself — the caller (StripeConfig / the controller)
# decides what to store and in which mode, exactly like PostmarkAccountSetup.
class StripeWebhookSetup
  class Error < StandardError; end

  # The events WebhooksController#stripe actually handles. Keep in lockstep
  # with that controller's `case event.type` — enabling more here just means
  # Roe receives events it ignores; enabling fewer means it silently misses
  # one. These four are the whole set today.
  ENABLED_EVENTS = %w[
    checkout.session.completed
    charge.refunded
    charge.dispute.created
    charge.dispute.closed
  ].freeze

  def initialize(secret_key)
    raise Error, "A Stripe secret key is required." if secret_key.to_s.strip.empty?

    @secret_key = secret_key.to_s.strip
  end

  # Find Roe's endpoint for this URL, if one exists. Returns the
  # Stripe::WebhookEndpoint or nil. Never raises for "not found".
  def find_endpoint(url)
    each_endpoint.find { |ep| ep.url == url }
  rescue Stripe::StripeError => e
    raise Error, stripe_message(e)
  end

  # Ensure a webhook endpoint exists at `url` with exactly Roe's event set,
  # and return one whose signing secret we captured. Because Stripe only
  # reveals the secret at creation, an existing Roe endpoint is deleted and
  # recreated so the returned secret is always usable.
  #
  # Returns a hash: { id:, signing_secret:, recreated: true|false }.
  def ensure_endpoint(url)
    raise Error, "No webhook URL available." if url.to_s.strip.empty?

    existing = find_endpoint(url)
    recreated = false

    if existing
      # Can't read its secret back; delete so the recreate below yields one.
      begin
        Stripe::WebhookEndpoint.delete(existing.id, {}, request_options)
        recreated = true
      rescue Stripe::StripeError => e
        raise Error, stripe_message(e)
      end
    end

    created = Stripe::WebhookEndpoint.create(
      { url: url, enabled_events: ENABLED_EVENTS, description: "Roe" },
      request_options
    )

    secret = created.respond_to?(:secret) ? created.secret : nil
    if secret.to_s.empty?
      raise Error, "Stripe created the webhook but returned no signing secret."
    end

    { id: created.id, signing_secret: secret, recreated: recreated }
  rescue Stripe::StripeError => e
    raise Error, stripe_message(e)
  end

  # Read-only registration check: is there an endpoint at this URL? Proves
  # configuration (registered + aimed at Roe), not that events flow. Never
  # raises — any API failure reads as "not configured".
  def endpoint_registered?(url)
    !find_endpoint(url).nil?
  rescue StandardError
    false
  end

  private

  def each_endpoint
    return enum_for(:each_endpoint) unless block_given?

    # auto_paging_each walks all pages; an account can hold up to 16 endpoints
    # so this is cheap, but paginate rather than assume one page.
    Stripe::WebhookEndpoint.list({ limit: 100 }, request_options).auto_paging_each do |ep|
      yield ep
    end
  end

  def request_options
    { api_key: @secret_key }
  end

  def stripe_message(error)
    # Stripe's own message is the useful part; surface it like PostmarkAccountSetup.
    msg = error.respond_to?(:message) ? error.message : error.to_s
    msg.presence || "Stripe request failed."
  end
end
