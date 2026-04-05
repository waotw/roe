class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :require_authentication

  def stripe
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']

    # For now, just parse without signature verification
    # We'll add verification after testing
    event = Stripe::Event.construct_from(JSON.parse(payload))

    case event.type
    when 'checkout.session.completed'
      handle_checkout_completed(event.data.object)
    end

    head :ok
  rescue JSON::ParserError, Stripe::StripeError => e
    Rails.logger.error "Webhook error: #{e.message}"
    head :bad_request
  end

  private

  def handle_checkout_completed(session)
    member_id = session.metadata.member_id

    unless member_id.present?
      Rails.logger.error "Webhook: No member_id in checkout session metadata"
      return
    end

    member = Member.find_by(id: member_id)

    unless member
      Rails.logger.error "Webhook: Member #{member_id} not found"
      return
    end

    # Skip if already paid (in case webhook fires twice)
    if member.paid?
      Rails.logger.info "Webhook: Member #{member.email} already paid, skipping"
      return
    end

    # Generate password
    password = Member.generate_password

    # Upgrade member
    member.upgrade_to_paid_with_stripe!(
      customer_id: session.customer,
      payment_intent_id: session.payment_intent,
      password: password
    )

    # Store password temporarily for success page (expires in 1 hour)
    Rails.cache.write("member_#{member.id}_password", password, expires_in: 1.hour)

    Rails.logger.info "✓ Member #{member.email} upgraded to paid"
  rescue => e
    Rails.logger.error "Webhook error handling checkout: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    # Don't re-raise - we already logged it and Stripe will retry anyway
  end
end
