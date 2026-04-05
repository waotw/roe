module Members
  class RegistrationsController < ApplicationController
    skip_before_action :require_authentication
    before_action :redirect_if_signed_in, only: [:new, :create]

    def new
      @member = Member.new
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
        render :new, status: :unprocessable_entity
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
            customer_email: @member.email,
            line_items: [{
              price: stripe_config.price_id,
              quantity: 1
            }],
            mode: 'payment',
            success_url: checkout_success_url + "?session_id={CHECKOUT_SESSION_ID}",
            cancel_url: checkout_cancel_url,
            metadata: {
              member_id: @member.id,
              member_email: @member.email
            }
          )

          redirect_to checkout_session.url, allow_other_host: true
        rescue Stripe::StripeError => e
          Rails.logger.error "Stripe checkout error: #{e.message}"
          redirect_to root_path, alert: "Payment setup failed. Please try again."
        end
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def registration_params
      params.require(:member).permit(:email, :name)
    end

    def redirect_if_signed_in
      redirect_to root_path if current_member
    end
  end
end
