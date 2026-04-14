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

  def product_breadcrumbs(product)
    return '' unless product
    return '' if product.metadata['breadcrumbs'] == false

    crumbs = []

    # Home
    crumbs << link_to('Home', '/', class: 'breadcrumb-link')

    # Store
    store_page = Page.find_by("metadata->>'url_name' = ?", 'store')
    if store_page
      crumbs << link_to('Store', '/store', class: 'breadcrumb-link')
    else
      crumbs << content_tag(:span, 'Store', class: 'breadcrumb-text')
    end

    # Category (if exists)
    if product.metadata['category'].present?
      category = product.metadata['category']
      category_page = Page.find_by("metadata->>'url_name' = ?", "store/#{category.parameterize}")

      if category_page
        crumbs << link_to(category.titleize, "/store/#{category.parameterize}", class: 'breadcrumb-link')
      else
        crumbs << content_tag(:span, category.titleize, class: 'breadcrumb-text')
      end
    end

    # Current product (not linked)
    crumbs << content_tag(:span, product.title, class: 'breadcrumb-current')

    content_tag(:nav, crumbs.join(' › ').html_safe, class: 'breadcrumbs', 'aria-label': 'Breadcrumb')
  end

  def duplicate_sku_warning
    duplicates = Product.duplicate_skus
    return nil if duplicates.empty?

    count = duplicates.values.flatten.count
    {
      message: "#{duplicates.keys.count} duplicate SKU(s) found affecting #{count} products",
      path: duplicate_skus_admin_products_path,
      severity: :error
    }
  end
end
