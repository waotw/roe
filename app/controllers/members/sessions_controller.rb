module Members
  class SessionsController < BaseController
    skip_before_action :set_current_member, only: [:new, :create]
    before_action :redirect_if_signed_in, only: [:new, :create]

    def new
      # Render sign in form
    end

    def create
      @member = Member.find_by(email: params[:email].downcase.strip)

      if @member&.authenticate(params[:password])
        if @member.active?
          session[:member_id] = @member.id
          redirect_back_or_to account_path, notice: "Welcome back!"
        else
          redirect_to signin_path, alert: "Your membership has been cancelled. Please contact support."
        end
      else
        flash.now[:alert] = "Invalid email or password"
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      session.delete(:member_id)
      redirect_to root_path, notice: "Signed out successfully"
    end

    private

    def redirect_if_signed_in
      redirect_to account_path if member_signed_in?
    end
  end
end
