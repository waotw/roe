class Admin::AccountController < Admin::BaseController
  def show
    @user = current_admin
    @unconsumed_code_count = @user.recovery_codes.unconsumed.count
    @total_code_count      = @user.recovery_codes.count
    # Plaintext codes flow in via flash on the redirect after a
    # regenerate. Shown once on this render, then gone — they're
    # not persisted anywhere.
    @plaintext_codes = flash[:plaintext_codes]
  end

  def update_email
    user = current_admin
    new_email = params[:email_address].to_s.strip

    if new_email.blank?
      flash[:alert] = "Email cannot be blank."
    elsif user.update(email_address: new_email)
      flash[:notice] = "Email updated to #{user.email_address}."
    else
      flash[:alert] = "Couldn't update email: #{user.errors.full_messages.to_sentence}"
    end
    redirect_to admin_account_path
  end

  def update_password
    user = current_admin
    current_password = params[:current_password].to_s
    new_password     = params[:password].to_s
    confirmation     = params[:password_confirmation].to_s

    if !user.authenticate(current_password)
      flash[:alert] = "Current password is incorrect."
    elsif new_password.blank? || new_password != confirmation
      flash[:alert] = "New password and confirmation must match and not be blank."
    elsif user.update(password: new_password)
      # Sign out everywhere else as a safety net after a credential
      # change. The current session survives because we exclude it
      # from the destroy.
      user.sessions.where.not(id: Current.session&.id).destroy_all
      flash[:notice] = "Password updated. Other active sessions have been signed out."
    else
      flash[:alert] = "Couldn't update password: #{user.errors.full_messages.to_sentence}"
    end
    redirect_to admin_account_path
  end

  def regenerate_recovery_codes
    user = current_admin
    plaintexts = user.generate_recovery_codes!
    # Surface plaintext ONCE on the next render via flash. Flash is
    # carried in the signed session cookie — 8 codes × ~14 chars sit
    # well under the cookie size limit.
    flash[:plaintext_codes] = plaintexts
    flash[:notice] = "Recovery codes regenerated. Save them now — they won't be shown again."
    redirect_to admin_account_path
  end

  private

  # Active admin User behind the current session. Authentication has
  # already populated Current.session via the before_action chain.
  def current_admin
    Current.session.user
  end
end
