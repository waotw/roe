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
    return unless helpers.members_enabled?
    return unless item.metadata["audience"] == "paid"

    # Admins can see all paid content
    return if authenticated?

    # Paid members get full access
    return if current_member&.paid? && current_member&.active?

    # Check if content has a paid_content form (acts as paywall)
    has_paywall_form = item.content.include?("for: paid_content")

    if has_paywall_form
      # Let the page load - content will be truncated at the form
      nil
    else
      # No form = redirect to upgrade page
      upgrade_page = Page.find_by("file_path LIKE ?", "%upgrade.md")
      upgrade_path = upgrade_page ? "/#{upgrade_page.url_name}" : "/upgrade"

      redirect_to upgrade_path, alert: "This content requires a paid membership"
    end
  end
end
