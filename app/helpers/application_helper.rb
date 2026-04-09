module ApplicationHelper
  def safe_system_image_path(filename, **options)
    return nil if filename.blank?
    system_image_path(filename, **options)
  rescue ActionController::UrlGenerationError
    nil
  end

  def safe_system_image_url(filename, **options)
    return nil if filename.blank?
    system_image_url(filename, **options)
  rescue ActionController::UrlGenerationError
    nil
  end

  # Safe media URL helpers for audio/video
  def safe_media_path(filename, **options)
    return nil if filename.blank?
    media_path(filename, **options)
  rescue ActionController::UrlGenerationError => e
    Rails.logger.warn "⚠️  Invalid media path: #{filename}"
    nil
  end

  def safe_media_url(filename, **options)
    return nil if filename.blank?
    media_url(filename, **options)
  rescue ActionController::UrlGenerationError => e
    Rails.logger.warn "⚠️  Invalid media URL: #{filename}"
    nil
  end

  def members_enabled?
    File.exist?(Rails.root.join('site/system/defaults/members.yml'))
  end

  def newsletters_enabled?
    members_enabled? && SiteConfig.default('members', 'newsletter')&.dig('enabled') == true
  end

  def postmark_configured?
    PostmarkConfig.exists? && PostmarkConfig.current.connected?
  end

  def requires_audience_on_publish?
    members_enabled?
  end

  def requires_published_to_on_publish?
    newsletters_enabled? && postmark_configured?
  end
end
