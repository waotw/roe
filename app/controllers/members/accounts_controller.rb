module Members
  class AccountsController < ApplicationController
    include MemberAuthentication

    skip_before_action :require_authentication
    before_action :require_member

    def show
      @member = current_member
      @private_feeds = PrivateFeeds.for(@member)
    end

    def edit
      @member = current_member
    end

    def update
      @member = current_member

      # Check if email is changing
      if account_params[:email].present? && account_params[:email] != @member.email
        # Store new email as pending and update name simultaneously
        @member.pending_email = account_params[:email]
        @member.name = account_params[:name] if account_params[:name].present?

        if @member.save
          @member.generate_email_confirmation_token!
          MemberMailer.email_confirmation(@member)

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

    # Issue a new media token, invalidating every private feed URL the member
    # has handed out. The whole reason media_token is separate from the
    # sign-in token is that these URLs travel — so being able to rotate one
    # without touching the other is the point.
    def regenerate_media_token
      current_member.regenerate_media_token!

      redirect_to account_path,
        notice: "New feed links created. Your old links have stopped working — " \
                "update your podcast app with the new ones below."
    end

    # Delete the account: erase the person, keep the record. See
    # Member#anonymize! for what survives and why.
    #
    # Typing DELETE is the confirmation. A dialog is too easy to click past for
    # something with no undo, and the word has to be produced deliberately.
    def destroy
      unless params[:confirm].to_s.strip.upcase == "DELETE"
        redirect_to account_path, alert: "Type DELETE to confirm you want to delete your account."
        return
      end

      current_member.anonymize!
      reset_session

      redirect_to root_path,
        notice: "Your account has been deleted. Your name and email address have been removed."
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
