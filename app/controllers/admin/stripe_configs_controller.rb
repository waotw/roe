module Admin
  class StripeConfigsController < ApplicationController
    layout 'application'

    def edit
      @stripe_config = StripeConfig.current
    end

    def update
      @stripe_config = StripeConfig.current

      # Build update params
      update_params = {}

      # Test keys
      if params[:stripe_config][:publishable_key_test].present?
        update_params[:publishable_key_test] = params[:stripe_config][:publishable_key_test]
      end

      if params[:stripe_config][:secret_key_test].present?
        update_params[:secret_key_test] = params[:stripe_config][:secret_key_test]
      end

      # Live keys (optional)
      if params[:stripe_config][:publishable_key_live].present?
        update_params[:publishable_key_live] = params[:stripe_config][:publishable_key_live]
      end

      if params[:stripe_config][:secret_key_live].present?
        update_params[:secret_key_live] = params[:stripe_config][:secret_key_live]
      end

      # Webhook signing secrets (one per mode)
      if params[:stripe_config][:webhook_signing_secret_test].present?
        update_params[:webhook_signing_secret_test] = params[:stripe_config][:webhook_signing_secret_test]
      end

      if params[:stripe_config][:webhook_signing_secret_live].present?
        update_params[:webhook_signing_secret_live] = params[:stripe_config][:webhook_signing_secret_live]
      end

      # Mode
      if params[:stripe_config][:mode].present?
        update_params[:mode] = params[:stripe_config][:mode]
      end

      # Use direct assignment (not update! to ensure custom setters work)
      update_params.each do |key, value|
        @stripe_config.public_send("#{key}=", value)
      end

      if @stripe_config.save
        flash[:notice] = "Stripe configuration updated successfully"
        redirect_to edit_admin_stripe_config_path
      else
        flash.now[:error] = "Failed to save Stripe configuration"
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @stripe_config = StripeConfig.current
      @stripe_config.disconnect!

      flash[:notice] = "Stripe account disconnected"
      redirect_to admin_configs_path
    end
  end
end
