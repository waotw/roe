class CheckoutController < ApplicationController
  skip_before_action :require_authentication
  before_action :require_member, only: [:create]

  def create
    # Ensure member is free tier
    unless current_member.tier_free?
      redirect_to root_path, alert: "You already have a paid membership"
      return
    end

    # Get Stripe config
    stripe_config = StripeConfig.current
    unless stripe_config.connected? && stripe_config.price_id.present?
      redirect_to root_path, alert: "Payments not available"
      return
    end

    # Create Stripe Checkout Session
    session = Stripe::Checkout::Session.create(
      {
        customer_email: current_member.email,
        mode: 'payment',
        line_items: [{
          price: stripe_config.price_id,
          quantity: 1
        }],
        success_url: checkout_payment_processing_url + "?session_id={CHECKOUT_SESSION_ID}",
        cancel_url: checkout_cancel_url,
        metadata: {
          member_id: current_member.id
        }
      },
      StripeConfig.request_options
    )

    redirect_to session.url, allow_other_host: true
  rescue Stripe::StripeError => e
    redirect_to root_path, alert: "Payment error: #{e.message}"
  end

  def payment_processing
    @session_id = params[:session_id]
    # If already paid, redirect to success page
    if current_member&.paid?
      redirect_to checkout_success_path
      return
    end
    # Load page for sidebar
    @page = Page.find_by("json_extract(metadata, '$.url_name') = ?", 'checkout-success')
  end

  def success
    # Load the checkout success markdown page
    @page = Page.find_by("json_extract(metadata, '$.url_name') = ?", 'checkout-success')
    if @page
      render 'pages/show'
    else
      render plain: "Thank you for your purchase!", status: :ok
    end
  end

  def cancel
    # Load page for sidebar
    @page = Page.find_by("json_extract(metadata, '$.url_name') = ?", 'checkout-cancel')
  end

  private

  def require_member
    unless current_member
      redirect_to signin_path, alert: "Please sign in first"
    end
  end
end
