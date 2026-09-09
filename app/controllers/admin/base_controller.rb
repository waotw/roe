class Admin::BaseController < ApplicationController
  before_action :require_authentication
  before_action :ensure_integration_files
  before_action :run_restore_check
  layout "admin"

  private

  # After a DB restore, verify (once) that the restored encrypted data is
  # readable with this host's credentials; flag a mismatch otherwise so the
  # Site Sync page can offer the backup's parked credentials. Gated by a
  # marker, so it's a cheap File.exist? on every other request.
  def run_restore_check
    SiteSync::RestoreCheck.run_if_pending!
  end

  # Drop the media-usage backlink cache after any mutating request. Used by
  # controllers that change what references media (config saves, media
  # upload/delete/rename) but don't go through a content model's after_commit.
  def invalidate_media_usage_index
    MediaUsageIndex.invalidate! unless request.get? || request.head?
  end

  # Ensure integration config files exist whenever a feature is enabled.
  # This covers the case where a user deletes an integration file manually —
  # it gets recreated with blank keys on the next admin page load.
  def ensure_integration_files
    if SiteFeature.payments_feature_enabled? && !SiteFeature.payments_integration_file?
      ConfigGenerator.new.generate_payments_config
    end

    # Email, not newsletters — members can't sign in without it.
    if SiteFeature.email_feature_enabled? && !SiteFeature.email_integration_file?
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
