module Members
  class RegistrationsController < ApplicationController
    skip_before_action :require_authentication
    before_action :redirect_if_signed_in, only: [ :new, :create, :create_and_checkout ]
    before_action :load_signup_page, only: [ :new, :create, :create_and_checkout ]

    # Declared after load_signup_page so @page is there to re-render with.
    # Keyed on the IP because the address is the attacker's to choose, and set
    # high enough that a room full of people signing up at an event won't reach
    # it. Signing up is the one thing that must never be refused wrongly.
    include RateLimited
    limit_requests :signup, only: :create, with: -> { too_many_signups }
    limit_requests :checkout, only: :create_and_checkout, with: -> { too_many_signups }

    def new
      @member = Member.new
    end

    def too_many_signups
      @member ||= Member.new
      flash.now[:alert] = "Too many sign-ups from this connection just now. Wait a minute and try again."
      render "pages/show", status: :too_many_requests
    end

    def create
      @member = Member.new(registration_params)
      @member.tier = :free
      @member.status = :active

      if @member.save
        # Auto-signin after signup
        session[:member_id] = @member.id
        redirect_to root_path, notice: "Welcome! You're signed up."
      else
        # Render the page template to preserve the full page content with form
        render "pages/show", status: :unprocessable_entity
      end
    end

    def create_and_checkout
      @member = Member.new(registration_params)
      @member.tier = :free
      @member.status = :active

      if @member.save
        # Auto-signin
        session[:member_id] = @member.id

        # Create Stripe checkout session
        stripe_config = StripeConfig.current

        unless stripe_config.connected? && stripe_config.price_id.present?
          redirect_to root_path, alert: "Payments are not configured"
          return
        end

        begin
          checkout_session = Stripe::Checkout::Session.create(
            {
              customer_email: @member.email,
              line_items: [ {
                price: stripe_config.price_id,
                quantity: 1
              } ],
              mode: "payment",
              success_url: checkout_success_url + "?session_id={CHECKOUT_SESSION_ID}",
              cancel_url: checkout_cancel_url,
              metadata: {
                member_id: @member.id,
                member_email: @member.email
              }
            },
            StripeConfig.request_options
          )

          redirect_to checkout_session.url, allow_other_host: true
        rescue Stripe::StripeError => e
          Rails.logger.error "Stripe checkout error: #{e.message}"
          redirect_to root_path, alert: "Payment setup failed. Please try again."
        end
      else
        # Render the page template to preserve the full page content with form
        render "pages/show", status: :unprocessable_entity
      end
    end

    private

    def registration_params
      params.require(:member).permit(:email, :name)
    end

    def redirect_if_signed_in
      redirect_to root_path if current_member
    end

    def load_signup_page
      # Load the signup page so sidebar and other page-specific features work
      @page = Page.find_by("json_extract(metadata, '$.url_name') = ?", "sign-up")
    end
  end
end
