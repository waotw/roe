class DonationsController < ApplicationController
  skip_before_action :require_authentication

  def create
    unless SiteFeature.donations_enabled?
      redirect_to root_path, alert: "Donations are not enabled" and return
    end

    amount_cents = parse_amount_cents(params[:amount])

    if amount_cents.nil?
      redirect_back fallback_location: root_path, alert: "Please choose or enter an amount." and return
    end

    if amount_cents < Donation::MIN_AMOUNT_CENTS
      redirect_back fallback_location: root_path,
                    alert: "Minimum donation is $#{Donation::MIN_AMOUNT_CENTS / 100}." and return
    end

    if amount_cents > Donation::MAX_AMOUNT_CENTS
      redirect_back fallback_location: root_path,
                    alert: "Maximum donation is $#{Donation::MAX_AMOUNT_CENTS / 100}." and return
    end

    stripe_config = StripeConfig.current
    unless stripe_config.connected?
      redirect_to root_path, alert: "Payments not available" and return
    end

    currency = (stripe_config.currency.presence || "usd").downcase

    session = Stripe::Checkout::Session.create(
      {
        mode: "payment",
        customer_email: current_member&.email,
        line_items: [ {
          quantity: 1,
          price_data: {
            currency: currency,
            unit_amount: amount_cents,
            product_data: { name: "Support #{site_title}" }
          }
        } ],
        success_url: donation_success_url + "?session_id={CHECKOUT_SESSION_ID}",
        cancel_url: donation_cancel_url,
        metadata: {
          purpose: "donation",
          member_id: current_member&.id
        }
      },
      StripeConfig.request_options
    )

    redirect_to session.url, allow_other_host: true
  rescue Stripe::StripeError => e
    Rails.logger.error "[Donations] Stripe error: #{e.message}"
    redirect_to root_path, alert: "Payment error: #{e.message}"
  end

  def success
    @session_id = params[:session_id]
    # The webhook records the Donation row asynchronously; we don't need
    # to look anything up here. The page just thanks the donor.
  end

  def cancel
    # Donor cancelled checkout — just render the cancel view.
  end

  private

  # Accepts either a preset (whole-dollar integer) or a free-form string
  # like "12.50", "$12.50", "12,50". Returns cents as an integer, or nil
  # if the input is unusable.
  def parse_amount_cents(raw)
    return nil if raw.blank?

    cleaned = raw.to_s.strip.delete("$").tr(",", ".")
    return nil unless cleaned.match?(/\A\d+(\.\d{1,2})?\z/)

    (cleaned.to_f * 100).round
  end

  def site_title
    SiteConfig.get("title").presence || "this site"
  end
end
