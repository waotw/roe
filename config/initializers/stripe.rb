Rails.application.config.to_prepare do
  # Load Stripe configuration from database
  # (using to_prepare ensures this runs after DB is ready)

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
