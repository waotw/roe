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

      if @member.update(account_params)
        redirect_to account_path, notice: "Account updated successfully"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def account_params
      params.require(:member).permit(:name, :email)
    end
  end
end
