class SiteController < ApplicationController
  skip_before_action :require_authentication
  layout "site"

  before_action :setup_theme_preview

  private

  # Check if user can view draft/unlisted content
  def check_draft_access!(item)
    return if item.published? || item.unlisted?
    return if authenticated? # Admins can see drafts

    raise ActiveRecord::RecordNotFound
  end

  # Check if user can access paid content
  def check_paid_access!(item)
    return unless members_enabled?
    return unless item.metadata['audience'] == 'paid'

    # Need this back:
    if current_member&.paid? && current_member&.active?
      return  # Let paid members through
    end

    redirect_to signin_path, alert: "This content requires a paid membership"
  end
end
