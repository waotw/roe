class RecoveryCodesController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> {
    redirect_to new_recovery_code_path, alert: "Too many attempts. Try again in a few minutes."
  }

  def new
  end

  def create
    email        = params[:email_address].to_s.strip.downcase
    code         = params[:recovery_code].to_s
    new_password = params[:password].to_s
    confirmation = params[:password_confirmation].to_s

    user    = User.find_by(email_address: email)
    matched = user&.find_unconsumed_recovery_code(code)

    unless matched
      # Generic copy so attackers can't probe which emails exist.
      redirect_to new_recovery_code_path(email_address: email),
                  alert: "That email + recovery code combination didn't match."
      return
    end

    if new_password.blank? || new_password != confirmation
      redirect_to new_recovery_code_path(email_address: email),
                  alert: "New password and confirmation must match and not be blank."
      return
    end

    User.transaction do
      user.update!(password: new_password)
      matched.consume!
      # Kill every other session — the lockout flow assumes the prior
      # credentials are compromised or lost, so existing tokens
      # shouldn't keep working.
      user.sessions.destroy_all
    end

    redirect_to new_session_path,
                notice: "Password reset using a recovery code. Sign in with your new password."
  end
end
