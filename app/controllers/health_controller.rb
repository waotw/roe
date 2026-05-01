class HealthController < ApplicationController
  skip_before_action :require_authentication

  def check
    checks = {
      media_writable: File.writable?(File.join(RoeSitePaths::SITE_PATH, 'media')),
      media_exists: Dir.exist?(File.join(RoeSitePaths::SITE_PATH, 'media')),
      system_assets_exists: Dir.exist?(File.join(RoeSitePaths::SITE_PATH, 'system', 'assets')),
      db_connected: ActiveRecord::Base.connection.active?
    }

    if checks.values.all?
      render json: { status: 'ok', checks: checks }, status: :ok
    else
      render json: { status: 'error', checks: checks }, status: :service_unavailable
    end
  end
end
