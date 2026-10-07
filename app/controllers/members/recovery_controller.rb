module Members
  # Password reset via a recovery code, for a site running with email off.
  # The member mirror of the admin RecoveryCodesController: same generic-error
  # discipline (never reveal which emails have accounts) and consume-on-use.
  #
  # Only reachable when the site is in password mode — with email on, members
  # reset by magic link and this flow has no reason to exist.
  class RecoveryController < ApplicationController
    skip_before_action :require_authentication
    before_action :require_password_mode
    before_action :load_recover_page
    include RateLimited
    limit_requests :recovery, only: :create, with: -> { too_many_attempts }

    def new
      # Renders the recover-account page (a Roe Page) with the form. Explicit
      # because there's no recovery/new.html.erb — the page content and form
      # live in the Page, same as create/reject render it.
      render "pages/show"
    end

    def create
      email        = params[:email].to_s.strip.downcase
      code         = params[:recovery_code].to_s
      new_password = params[:password].to_s
      confirmation = params[:password_confirmation].to_s

      member  = Member.find_by(email: email)
      matched = member&.find_recovery_code(code)

      # Generic copy so attackers can't probe which emails exist: a wrong email
      # (no member) or a non-matching code both land here.
      if matched.nil?
        return reject("That email + recovery code combination didn't match.")
      elsif matched.consumed?
        # Only someone holding a real high-entropy code reaches here — safe to
        # be specific, and far more useful than "didn't match".
        return reject("That recovery code has already been used. Try one of your other saved codes.")
      end

      if new_password.blank? || new_password != confirmation
        return reject("New password and confirmation must match and not be blank.")
      end

      Member.transaction do
        member.update!(password: new_password)
        matched.consume!
      end

      # Sign them straight in: whoever completed this held a valid, unconsumed
      # recovery code AND set a new password — a stronger proof than a normal
      # sign-in, so re-typing the password they just chose would be friction,
      # not security. reset_session first guards against session fixation (an
      # attacker who planted a session cookie can't ride it into the now-
      # authenticated session). Guarded on active? so a suspended member can't
      # reset into an active session.
      if member.active?
        reset_session
        session[:member_id] = member.id
        redirect_to root_path, notice: "Password updated and you're signed in."
      else
        redirect_to "/sign-in", notice: "Password reset using a recovery code. Sign in with your new password."
      end
    end

    private

    def reject(message)
      flash.now[:alert] = message
      render "pages/show", status: :unprocessable_entity
    end

    def too_many_attempts
      flash.now[:alert] = "Too many attempts. Try again in a few minutes."
      render "pages/show", status: :too_many_requests
    end

    def require_password_mode
      redirect_to "/sign-in" unless SiteFeature.member_passwords_enabled?
    end

    def load_recover_page
      @page = Page.find_by("json_extract(metadata, '$.url_name') = ?", "recover-account")
    end
  end
end
