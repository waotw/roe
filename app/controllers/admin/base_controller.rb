class Admin::BaseController < ApplicationController
  before_action :require_authentication
  layout "application"

  private

  # Gate for production-only features (members admin, integrations,
  # paid memberships, etc.). Controllers opt in with:
  #
  #   before_action :require_production_features
  def require_production_features
    return if SiteFeature.show_production_features?
    redirect_to admin_root_path,
                alert: "This feature is only available in production."
  end

  # Gate for development-only features (Substack importer, Tools menu,
  # anything used to set up content before deploying to live).
  def require_development_features
    return if SiteFeature.show_development_features?
    redirect_to admin_root_path,
                alert: "This feature is only available in local development."
  end
end
