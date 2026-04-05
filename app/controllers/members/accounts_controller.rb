module Members
  class AccountsController < ApplicationController
    include MemberAuthentication

    skip_before_action :require_authentication
    before_action :require_member

    def show
      @member = current_member
    end

    def edit
      @member = current_member
    end

    def update
      @member = current_member

      # Check if email is changing
      if account_params[:email].present? && account_params[:email] != @member.email
        # Store new email as pending and send confirmation
        @member.pending_email = account_params[:email]

        if @member.save
          @member.generate_email_confirmation_token!
          MemberMailer.email_confirmation(@member).deliver_later

          redirect_to account_path, notice: "A confirmation email has been sent to #{@member.pending_email}. Click the link to confirm your new email address."
        else
          render :edit, status: :unprocessable_entity
        end
      else
        # Just updating name or other fields
        if @member.update(account_params.except(:email))
          redirect_to account_path, notice: "Account updated successfully"
        else
          render :edit, status: :unprocessable_entity
        end
      end
    end

    def confirm_email
      @member = current_member
      token = params[:token]

      if @member.confirm_email!(token)
        redirect_to account_path, notice: "Email address confirmed successfully!"
      else
        redirect_to account_path, alert: "Invalid or expired confirmation link."
      end
    end

    private

    def account_params
      params.require(:member).permit(:name, :email)
    end
  end
end
