class Current < ActiveSupport::CurrentAttributes
  attribute :session, :user, :member  # user = admin, member = public

  # Admin helpers
  def admin?
    user.present?
  end

  # Member helpers
  def can_access_premium?
    member&.paid? && member&.active?
  end
end
