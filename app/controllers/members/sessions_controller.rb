module Members
  class SessionsController < BaseController
    skip_before_action :set_current_member, only: [:new, :create, :signin_with_token]
    before_action :redirect_if_signed_in, only: [:new, :create]

    def new
      # Render sign in form
    end

    def create
      member = Member.find_by(email: params[:member][:email])

      if member&.active?
        member.regenerate_token!

        # Send magic link email immediately (no .deliver_now needed)
        MemberMailer.magic_link(member)

        # Redirect to confirmation page instead of home
        check_email_page = Page.find_by("json_extract(metadata, '$.url_name') = ?", 'check-email')
        if check_email_page
          redirect_to "/#{check_email_page.url_name}"
        else
          redirect_to root_path, notice: "Check your email for a sign-in link!"
        end
      else
        flash.now[:alert] = "No account found with that email"
        @page = Page.find_by("json_extract(metadata, '$.url_name') = ?", 'sign-in')
        render 'pages/show', status: :unprocessable_entity
      end
    end

    def destroy
      session.delete(:member_id)
      redirect_to root_path, notice: "Signed out successfully"
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
