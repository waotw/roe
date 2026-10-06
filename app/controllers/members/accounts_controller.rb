module Members
  class AccountsController < ApplicationController
    include MemberAuthentication

    skip_before_action :require_authentication
    before_action :require_member

    def show
      @member = current_member
      @private_feeds = PrivateFeeds.for(@member)
      # Receipt link for paid members, fetched live from Stripe (see
      # Member#stripe_receipt_url — rescued, so a Stripe hiccup just hides it).
      @receipt_url = @member.stripe_receipt_url if @member.paid?
    end

    def edit
      @member = current_member
    end

    def update
      @member = current_member

      # Check if email is changing
      if account_params[:email].present? && account_params[:email] != @member.email
        if SiteFeature.email_feature_enabled?
          # Email on: confirm the new address before it takes effect. The member
          # could be using email to sign in, so an unverified change could lock
          # them out — the confirmation link proves they own the new address.
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
          # Email off: email isn't a login credential (members sign in with a
          # password), so there's no mailer to confirm with and nothing to
          # protect. Apply the change immediately — it's just a contact address
          # for the Stripe receipt. No pending_email, no token, no email.
          @member.email = account_params[:email]
          @member.name = account_params[:name] if account_params[:name].present?

          if @member.save
            redirect_to account_path, notice: "Email updated"
          else
            render :edit, status: :unprocessable_entity
          end
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

    # Newsletter on or off. The token route in SubscriptionsController serves
    # the email links; this is the same switch for someone already signed
    # in. A bounced address can't be resubscribed from here — the problem
    # is delivery, not consent — so the form only offers the two real moves.
    def update_newsletter
      member = current_member

      case params[:newsletter]
      when "unsubscribe"
        member.unsubscribe_from_newsletter!
        redirect_to account_path, notice: "You've been unsubscribed from the newsletter."
      when "subscribe"
        if member.newsletter_status_bounced?
          redirect_to account_path, alert: "Email to this address has bounced, so the newsletter can't be turned back on. Change your email address first."
        else
          member.resubscribe_to_newsletter!
          redirect_to account_path, notice: "You're subscribed to the newsletter."
        end
      else
        redirect_to account_path, alert: "Nothing changed."
      end
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

      current_member.anonymize!(by: :member)
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

    # Fresh recovery codes for a password-mode (email-off) member, shown once
    # via flash. Replaces any existing set. No-op guard for email-on sites,
    # where recovery is by magic link and codes have no meaning.
    def regenerate_recovery_codes
      unless SiteFeature.member_passwords_enabled?
        redirect_to account_path and return
      end

      flash[:recovery_codes] = current_member.generate_recovery_codes!
      redirect_to account_path, notice: "New recovery codes generated. Save them below — your old codes have stopped working, and this is the only time these are shown."
    end

    private

    def account_params
      params.require(:member).permit(:name, :email)
    end
  end
end
