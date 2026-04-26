Rails.application.config.to_prepare do
  # Boot-time warm-up only. The global Stripe.api_key is NOT the source
  # of truth at request time — call sites pass `StripeConfig.request_options`
  # so each call uses the currently configured key (test vs live can be
  # toggled in admin without a server restart). Setting the global here
  # is harmless; some Stripe SDK paths still consult it as a fallback.

  begin
    stripe_config = StripeConfig.current

    if stripe_config.connected?
      Stripe.api_key = stripe_config.current_secret_key
      Rails.logger.info "✓ Stripe configured (#{stripe_config.mode} mode)"
    else
      Rails.logger.warn "⚠ Stripe not connected - add API keys in admin"
    end
  rescue => e
    # Handle case where DB doesn't exist yet (initial setup)
    Rails.logger.warn "⚠ Stripe config not loaded: #{e.message}"
  end
end
