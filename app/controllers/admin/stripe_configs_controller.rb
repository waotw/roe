module Admin
  class StripeConfigsController < Admin::BaseController
    layout 'application'

    def edit
      @stripe_config = StripeConfig.current
      @test_config = StripeConfig.test_config
    end

    def update
      @stripe_config = StripeConfig.current

      # Save test keys to file (all environments)
      test_config_data = {}
      test_config_data['publishable_key']       = params[:stripe_config][:publishable_key_test]       if params[:stripe_config][:publishable_key_test].present?
      test_config_data['secret_key']            = params[:stripe_config][:secret_key_test]            if params[:stripe_config][:secret_key_test].present?
      test_config_data['webhook_signing_secret'] = params[:stripe_config][:webhook_signing_secret_test] if params[:stripe_config][:webhook_signing_secret_test].present?

      StripeConfig.save_test_config(test_config_data) if test_config_data.any?

      # Live keys — production only; show a notice in dev so it's not silent
      if params[:stripe_config][:publishable_key_live].present? ||
         params[:stripe_config][:secret_key_live].present? ||
         params[:stripe_config][:webhook_signing_secret_live].present?

        if Rails.env.production?
          @stripe_config.publishable_key_live       = params[:stripe_config][:publishable_key_live]       if params[:stripe_config][:publishable_key_live].present?
          @stripe_config.secret_key_live            = params[:stripe_config][:secret_key_live]            if params[:stripe_config][:secret_key_live].present?
          @stripe_config.webhook_signing_secret_live = params[:stripe_config][:webhook_signing_secret_live] if params[:stripe_config][:webhook_signing_secret_live].present?
        else
          flash.now[:notice] = "Live keys are only saved in production. Test keys were saved."
        end
      end

      # Update mode
      @stripe_config.mode = params[:stripe_config][:mode] if params[:stripe_config][:mode].present?

      if @stripe_config.save
        # Verify asynchronously — result shown on next page load via Stimulus
        @stripe_config.verify!
        flash[:notice] = "Stripe configuration updated"
        redirect_to edit_admin_stripe_config_path
      else
        flash.now[:error] = "Failed to save Stripe configuration"
        @test_config = StripeConfig.test_config
        render :edit, status: :unprocessable_entity
      end
    end

    def verify
      @stripe_config = StripeConfig.current
      success = @stripe_config.verify!

      render json: {
        verified: success,
        verified_at: success ? @stripe_config.verified_at.iso8601 : nil,
        error: success ? nil : "Could not connect to Stripe. Check your keys."
      }
    end

    def destroy
      @stripe_config = StripeConfig.current
      @stripe_config.disconnect!

      flash[:notice] = "Stripe account disconnected"
      redirect_to admin_configs_path
    end
  end
end
