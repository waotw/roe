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
      # Paid only (members.yml free_signup: false): no free accounts, even
      # from a form posted here directly. The form itself has no free button.
      if SiteFeature.paid_only_signup?
        @member = Member.new(registration_params)
        @member.errors.add(:base, "This site doesn't offer free membership. Join with the paid option instead.") # COPY
        render "pages/show", status: :unprocessable_entity
        return
      end

      @member = Member.new(registration_params)
      @member.tier = :free
      @member.status = :active

      # Password mode (email off): a password is required at signup — it's the
      # only way the member will ever sign in, there's no magic link fallback.
      if SiteFeature.member_passwords_enabled? && params.dig(:member, :password).blank?
        @member.errors.add(:password, "can't be blank")
        render "pages/show", status: :unprocessable_entity
        return
      end

      if @member.save
        # Auto-signin after signup
        session[:member_id] = @member.id

        # Password mode: give the member recovery codes now and show them once —
        # with no email, this is their only way back in after a forgotten
        # password. flash.now can't survive a redirect, so stash for one display.
        if SiteFeature.member_passwords_enabled?
          flash[:recovery_codes] = @member.generate_recovery_codes!
          redirect_to account_path, notice: "You're signed up. Save your recovery codes below — you'll need one to reset your password, and this is the only time they're shown."
        else
          redirect_to root_path, notice: "Welcome! You're signed up."
        end
      else
        # Render the page template to preserve the full page content with form
        render "pages/show", status: :unprocessable_entity
      end
    end

    def create_and_checkout
      paid_only = SiteFeature.paid_only_signup?
      @member = paid_only ? pending_member_for_signup : Member.new(registration_params)
      @member.tier = :free
      # Paid only: the account stays pending, and signed out, until Stripe
      # confirms the payment (WebhooksController#handle_checkout_completed).
      # Otherwise it's a free member straight away, upgraded on payment.
      @member.status = paid_only ? :pending : :active

      if @member.save
        if paid_only
          # Not signed in yet: a pending account must not get member access.
          # payment_processing signs them in once the payment is confirmed.
          session[:pending_member_id] = @member.id
        else
          # Auto-signin
          session[:member_id] = @member.id
        end

        # Create Stripe checkout session
        stripe_config = StripeConfig.current

        unless stripe_config.connected? && stripe_config.current_price_id.present?
          redirect_to root_path, alert: "There was an issue with the upgrade system. Please contact the site owner."
          return
        end

        # Paid only lands on the processing page, which waits for the payment
        # to be confirmed and then signs the member in.
        success_url = paid_only ? checkout_payment_processing_url : checkout_success_url

        begin
          checkout_session = Stripe::Checkout::Session.create(
            {
              customer_email: @member.email,
              line_items: [ {
                price: stripe_config.current_price_id,
                quantity: 1
              } ],
              mode: "payment",
              success_url: success_url + "?session_id={CHECKOUT_SESSION_ID}",
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
      # Password is permitted so a password-mode (email off) signup can set one;
      # has_secure_password ignores a blank password, so email-mode signups that
      # never send the field are unaffected.
      params.require(:member).permit(:email, :name, :password)
    end

    # Someone who closed the Stripe page and tries again has a pending account
    # under that email already; reuse it rather than refusing the email as
    # taken. Only pending accounts are reused, never an active one.
    def pending_member_for_signup
      email = registration_params[:email].to_s.strip
      existing = Member.status_pending.where("LOWER(email) = ?", email.downcase).first if email.present?
      return Member.new(registration_params) unless existing

      existing.assign_attributes(registration_params.except(:email))
      existing
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
