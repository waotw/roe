module Members
  class RegistrationsController < ApplicationController
    skip_before_action :require_authentication
    before_action :redirect_if_signed_in, only: [:new, :create]

    def new
      @member = Member.new
    end

    def create
      @member = Member.new(registration_params)
      @member.tier = :free
      @member.status = :active

      if @member.save
        # Auto-signin after signup
        session[:member_id] = @member.id
        redirect_to root_path, notice: "Welcome! You're signed up."
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def registration_params
      params.require(:member).permit(:email, :name)
    end

    def redirect_if_signed_in
      redirect_to root_path if current_member
    end
  end
end
