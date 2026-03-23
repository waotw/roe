class HealthController < ApplicationController
  skip_before_action :require_authentication

  def check
    checks = {
      media_writable: File.writable?(Rails.root.join('site', 'media')),
      media_exists: Dir.exist?(Rails.root.join('site', 'media')),
      system_assets_exists: Dir.exist?(Rails.root.join('site', 'system', 'assets')),
      db_connected: ActiveRecord::Base.connection.active?
    }

    if checks.values.all?
      render json: { status: 'ok', checks: checks }, status: :ok
    else
      render json: { status: 'error', checks: checks }, status: :service_unavailable
    end
  end
end
