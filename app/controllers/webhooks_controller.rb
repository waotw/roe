class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :require_authentication

  def stripe
    payload = request.body.read
    sig_header = request.env["HTTP_STRIPE_SIGNATURE"]
    signing_secret = StripeConfig.current.current_webhook_signing_secret

    event = if signing_secret.present?
              # Verified path. Stripe::Webhook.construct_event raises
              # SignatureVerificationError on tampered or forged payloads.
              Stripe::Webhook.construct_event(payload, sig_header, signing_secret)
    else
              # Unverified fallback for fresh installs or local development
              # where the writer hasn't pasted in the signing secret yet.
              # Logged loudly so it's not silently insecure forever.
              Rails.logger.warn "[Webhook] No signing secret configured for #{StripeConfig.current.mode} mode — accepting unverified payload. Add it in admin → Stripe Configuration."
              Stripe::Event.construct_from(JSON.parse(payload))
    end

    case event.type
    when "checkout.session.completed"
      session = event.data.object
      # Branch on metadata.purpose. Member upgrade flow predates donations
      # and doesn't set the purpose key — treat that as the default for
      # back-compat with existing live webhooks. Use bracket access so
      # absent keys return nil instead of raising NoMethodError.
      if session.metadata&.[]("purpose") == "donation"
        handle_donation_completed(session)
      else
        handle_checkout_completed(session)
      end
    when "charge.refunded"
      handle_charge_refunded(event.data.object)
    when "charge.dispute.created"
      handle_dispute_created(event.data.object)
    when "charge.dispute.closed"
      handle_dispute_closed(event.data.object)
    end

    head :ok
  rescue Stripe::SignatureVerificationError => e
    Rails.logger.error "[Webhook] Signature verification failed: #{e.message}"
    head :bad_request
  rescue JSON::ParserError, Stripe::StripeError => e
    Rails.logger.error "Webhook error: #{e.message}"
    head :bad_request
  end

  private

  def handle_checkout_completed(session)
    member_id = session.metadata&.[]("member_id")

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

    # Upgrade member — also snapshots the amount paid so the dashboard
    # can report total membership revenue without round-tripping to Stripe.
    member.upgrade_to_paid_with_stripe!(
      customer_id: session.customer,
      payment_intent_id: session.payment_intent,
      password: password,
      amount_cents: session.amount_total,
      currency: session.currency
    )

    # Store password temporarily for success page (expires in 1 hour)
    Rails.cache.write("member_#{member.id}_password", password, expires_in: 1.hour)

    Rails.logger.info "✓ Member #{member.email} upgraded to paid"
  rescue => e
    Rails.logger.error "Webhook error handling checkout: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    # Don't re-raise - we already logged it and Stripe will retry anyway
  end

  def handle_donation_completed(session)
    # Idempotent: if Stripe re-delivers this webhook we don't double-record.
    if Donation.exists?(stripe_session_id: session.id)
      Rails.logger.info "Webhook: Donation for session #{session.id} already recorded"
      return
    end

    email = session.customer_details&.email || session.customer_email
    # `session.metadata.member_id` raises NoMethodError when the key is
    # absent (anonymous donations don't set it). Bracket access returns
    # nil for missing keys.
    member_id = session.metadata&.[]("member_id").presence

    Donation.create!(
      amount_cents: session.amount_total,
      currency: session.currency,
      email: email,
      stripe_session_id: session.id,
      stripe_payment_intent_id: session.payment_intent,
      member_id: member_id
    )

    Rails.logger.info "✓ Donation recorded: #{email} — #{session.amount_total} #{session.currency}"
  rescue => e
    Rails.logger.error "Webhook error handling donation: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  # Stripe fires charge.refunded once per refund event. The charge's
  # amount_refunded field is *cumulative* (all refunds on this charge),
  # so we just overwrite our snapshot each time. Idempotent.
  def handle_charge_refunded(charge)
    pi = charge.payment_intent
    Rails.logger.info "[Webhook] charge.refunded received — charge=#{charge.id} payment_intent=#{pi.inspect} amount_refunded=#{charge.amount_refunded}"

    if pi.blank?
      Rails.logger.warn "[Webhook] charge.refunded without payment_intent — ignoring (charge #{charge.id})"
      return
    end

    refund_attrs = {
      refunded_at: Time.current,
      refunded_amount_cents: charge.amount_refunded,
      refunded_currency: charge.currency
    }

    if (donation = Donation.find_by(stripe_payment_intent_id: pi))
      donation.update!(refund_attrs)
      Rails.logger.info "✓ Donation refunded: #{donation.email} — #{charge.amount_refunded} #{charge.currency}"
    elsif (member = Member.find_by(stripe_payment_intent_id: pi))
      # Auto-downgrade refunded paid members to free. They no longer
      # have a valid claim to paid content. Admin can manually re-grant
      # if the refund was an error.
      member.update!(refund_attrs.merge(tier: :free))
      Rails.logger.info "✓ Member refunded and downgraded to free: #{member.email} — #{charge.amount_refunded} #{charge.currency}"
    else
      Rails.logger.info "[Webhook] charge.refunded for unknown payment_intent #{pi} — ignoring (no Donation or Member matched)"
    end
  rescue => e
    Rails.logger.error "Webhook error handling refund: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  def handle_dispute_created(dispute)
    record = Dispute.find_or_initialize_by(stripe_dispute_id: dispute.id)
    record.assign_attributes(
      stripe_charge_id: dispute.charge,
      amount_cents: dispute.amount,
      currency: dispute.currency,
      status: :open
    )
    record.save!
    Rails.logger.info "⚠ Dispute opened: #{dispute.id} — #{dispute.amount} #{dispute.currency}"
  rescue => e
    Rails.logger.error "Webhook error handling dispute.created: #{e.message}"
  end

  def handle_dispute_closed(dispute)
    record = Dispute.find_by(stripe_dispute_id: dispute.id)
    if record
      record.update!(status: :closed)
      Rails.logger.info "✓ Dispute closed: #{dispute.id}"
    else
      # We never saw the create event (could happen if Roe was offline
      # when it fired). Record it as already-closed so it doesn't show
      # up in the open-disputes count.
      Dispute.create!(
        stripe_dispute_id: dispute.id,
        stripe_charge_id: dispute.charge,
        amount_cents: dispute.amount,
        currency: dispute.currency,
        status: :closed
      )
      Rails.logger.info "✓ Dispute closed (created retroactively): #{dispute.id}"
    end
  rescue => e
    Rails.logger.error "Webhook error handling dispute.closed: #{e.message}"
  end
end
