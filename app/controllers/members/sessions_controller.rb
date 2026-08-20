module Members
  class SessionsController < BaseController
    include RateLimited

    skip_before_action :set_current_member, only: [ :new, :create, :signin_with_token ]
    before_action :redirect_if_signed_in, only: [ :new, :create ]

    # Counted per address, not per IP. Flooding one person's inbox is abuse of
    # that address; an IP limit here would punish everyone behind a shared
    # connection — an office, a campus, a whole mobile network — for something
    # one of them did.
    #
    # And hitting it doesn't refuse the sign-in. It stops sending another email
    # and says one is already on its way, which is true and is what someone
    # clicking twice needed to hear. Nobody is turned away.
    limit_requests :magic_link, only: :create, with: -> { link_already_sent }

    # Token guessing. Nothing narrower than the IP to key on here, and a guess
    # is cheap, so the allowance is high enough that a person following links
    # from their own inbox will never see it.
    limit_requests :token, only: :signin_with_token, with: -> {
      redirect_to root_path, alert: "Too many sign-in attempts. Try again shortly."
    }

    def new
      # Render sign in form
    end

    def create
      member = Member.find_by(email: params[:member][:email])

      if member&.active?
        member.regenerate_token!

        # Send magic link email immediately (no .deliver_now needed)
        MemberMailer.magic_link(member)

        redirect_to_check_email
      else
        flash.now[:alert] = "No account found with that email"
        @page = Page.find_by("json_extract(metadata, '$.url_name') = ?", "sign-in")
        render "pages/show", status: :unprocessable_entity
      end
    end

    def destroy
      session.delete(:member_id)
      redirect_to root_path, notice: "Signed out successfully"
    end

    # Same destination as a successful send — from the reader's side nothing has
    # gone wrong, and a link really is waiting for them.
    def link_already_sent
      redirect_to_check_email(notice: "We've already sent a sign-in link — check your email, including spam.")
    end

    def redirect_to_check_email(notice: nil)
      page = Page.find_by("json_extract(metadata, '$.url_name') = ?", "check-email")
      if page
        redirect_to "/#{page.url_name}", notice: notice
      else
        redirect_to root_path, notice: notice || "Check your email for a sign-in link!"
      end
    end

    def signin_with_token
      member = Member.find_by(access_token: params[:token])

      if member&.active?
        session[:member_id] = member.id
        redirect_to root_path, notice: "Signed in successfully"
      else
        redirect_to signin_path, alert: "Invalid or expired link"
      end
    end

    private

    def redirect_if_signed_in
      redirect_to account_path if member_signed_in?
    end
  end
end
