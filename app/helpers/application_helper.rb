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
    File.exist?(Rails.root.join('site/system/features/members.yml'))
  end

  def store_enabled?
    File.exist?(Rails.root.join('site', 'system', 'features', 'store.yml'))
  end

  def snipcart_connected?
    store_enabled? && SnipcartConfig.current&.connected?
  end

  def newsletters_enabled?
    members_enabled? && SiteConfig.feature('members', 'newsletter.enabled') == true
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

  def store_currency_symbol
    currency = SiteConfig.feature('store', 'currency') || 'usd'
    case currency.downcase
    when 'usd' then '$'
    when 'eur' then '€'
    when 'gbp' then '£'
    when 'cad' then 'CA$'
    when 'aud' then 'A$'
    when 'jpy' then '¥'
    else currency.upcase
    end
  end
end
