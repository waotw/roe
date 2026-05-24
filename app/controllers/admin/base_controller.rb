class Admin::BaseController < ApplicationController
  before_action :require_authentication
  before_action :ensure_integration_files
  layout "application"

  private

  # Ensure integration config files exist whenever a feature is enabled.
  # This covers the case where a user deletes an integration file manually —
  # it gets recreated with blank keys on the next admin page load.
  def ensure_integration_files
    if SiteFeature.payments_feature_enabled? && !SiteFeature.payments_integration_file?
      ConfigGenerator.new.generate_payments_config
    end

    if SiteFeature.newsletters_feature_enabled? && !SiteFeature.newsletters_integration_file?
      ConfigGenerator.new.generate_newsletters_config
    end

    if SiteFeature.store_enabled? && !SiteFeature.snipcart_integration_file?
      ConfigGenerator.new.generate_snipcart_config
    end
  end

  def require_members_feature
    return if SiteFeature.members_enabled?
    redirect_to admin_root_path,
                alert: "Members feature is not enabled. Configure it in site/system/features/"
  end

  def require_store_feature
    return if SiteFeature.store_enabled?
    redirect_to admin_root_path,
                alert: "Store feature is not enabled. Configure it in site/system/features/"
  end
end
