class CheckoutController < ApplicationController
  skip_before_action :require_authentication
  before_action :require_checkout_member, only: [ :create ]

  def create
    member = checkout_member

    # Ensure member is free tier
    unless member.tier_free?
      redirect_to root_path, alert: "You already have a paid membership"
      return
    end

    # Get Stripe config
    stripe_config = StripeConfig.current
    unless stripe_config.connected? && stripe_config.current_price_id.present?
      redirect_to root_path, alert: "There was an issue with the upgrade system. Please contact the site owner."
      return
    end

    # Create Stripe Checkout Session
    session = Stripe::Checkout::Session.create(
      {
        customer_email: member.email,
        mode: "payment",
        line_items: [ {
          price: stripe_config.current_price_id,
          quantity: 1
        } ],
        success_url: checkout_payment_processing_url + "?session_id={CHECKOUT_SESSION_ID}",
        cancel_url: checkout_cancel_url,
        metadata: {
          member_id: member.id
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

    # Paid-only sign-up: the account waits, signed out, until the webhook
    # confirms the payment. Once it's active and paid, sign them in here.
    sign_in_confirmed_pending_member

    # If already paid, redirect to success page
    if current_member&.paid?
      redirect_to checkout_success_path
      return
    end
    # Load page for sidebar
    @page = Page.find_by("json_extract(metadata, '$.url_name') = ?", "checkout-success")
  end

  def success
    # Load the checkout success markdown page
    @page = Page.find_by("json_extract(metadata, '$.url_name') = ?", "checkout-success")
    if @page
      render "pages/show"
    else
      render plain: "Thank you for your purchase!", status: :ok
    end
  end

  def cancel
    # Load page for sidebar
    @page = Page.find_by("json_extract(metadata, '$.url_name') = ?", "checkout-cancel")
    # A paid-only sign-up that left Stripe without paying: say the account
    # waits on the payment, and Try Again picks it up.
    @pending_member = pending_member_from_session
  end

  private

  # Who a checkout is for: the signed-in member upgrading, or a paid-only
  # sign-up that hasn't paid yet (signed out, so it's held in the session by
  # Members::RegistrationsController#create_and_checkout).
  def checkout_member
    current_member || pending_member_from_session
  end

  def require_checkout_member
    require_member unless checkout_member
  end

  def pending_member_from_session
    pending_id = session[:pending_member_id]
    return unless pending_id

    Member.status_pending.find_by(id: pending_id)
  end

  def sign_in_confirmed_pending_member
    pending_id = session[:pending_member_id]
    return unless pending_id

    member = Member.find_by(id: pending_id)
    return unless member&.status_active? && member.paid?

    session.delete(:pending_member_id)
    session[:member_id] = member.id
    Current.member = member
  end

  def require_member
    unless current_member
      redirect_to signin_path, alert: "Please sign in first"
    end
  end
end
