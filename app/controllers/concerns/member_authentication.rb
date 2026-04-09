module MemberAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :set_current_member
    helper_method :current_member, :member_signed_in?, :can_access_premium?
  end

  private

  def set_current_member
    if session[:member_id]
      Current.member = Member.find_by(id: session[:member_id])
    end
  end

  def current_member
    Current.member
  end

  def member_signed_in?
    current_member.present?
  end

  def can_access_premium?
    current_member&.paid? && current_member&.active?
  end

  def require_member
    unless member_signed_in?
      store_location
      redirect_to "/sign-in", alert: "Please sign in to continue"  # Use path string, not named route
    end
  end

  def require_paid_member
    unless can_access_premium?
      redirect_to "/upgrade", alert: "This content requires a paid membership"
    end
  end

  def store_location
    session[:member_return_to] = request.fullpath if request.get? && !request.xhr?
  end

  def redirect_back_or_to(default, **options)
    redirect_to session.delete(:member_return_to) || default, **options
  end
end
