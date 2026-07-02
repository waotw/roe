module ApplicationHelper
  def site_title
    SiteConfig.get("title").presence || "(set site title in Settings → site)"
  end

  # Reads an SVG from site/system/assets/images/ and returns it as inline
  # HTML so CSS (currentColor, width/height via class) can style it directly.
  # Falls back to an <img> tag via system_image_path if the file isn't found
  # or isn't an SVG, and returns nil if the filename is blank.
  def inline_system_svg(filename, **html_options)
    return nil if filename.blank?
    return nil unless filename.end_with?(".svg")

    path = File.join(RoeSitePaths::SITE_PATH, "system", "assets", "images", filename)
    return nil unless File.exist?(path)

    svg = File.read(path)

    # Merge any html_options (class, title, aria-label, etc.) onto the root <svg> element
    unless html_options.empty?
      svg = svg.sub(/<svg([^>]*)>/i) do
        tag_attrs = $1
        html_options.each do |key, value|
          attr = key.to_s.dasherize
          if tag_attrs =~ /#{attr}="[^"]*"/
            tag_attrs = tag_attrs.gsub(/#{attr}="[^"]*"/, "#{attr}=\"#{value}\"")
          else
            tag_attrs += " #{attr}=\"#{value}\""
          end
        end
        "<svg#{tag_attrs}>"
      end
    end

    svg.html_safe
  end

  # Reads the persistent update-available flag written by CheckForUpdatesJob.
  # No network call — just a cache read. The flag has no TTL so the dot
  # stays visible across restarts until an update completes.
  def update_available?
    Rails.cache.read(RoeUpdater::VersionChecker::UPDATE_AVAILABLE_KEY) == true
  end

  # Returns a CSP nonce safe to embed in inline <script>/<style> tags,
  # or nil when CSP isn't active for this render. The nil case matters
  # for the static-site generator: ApplicationController.render builds
  # a synthesized request whose middleware stack hasn't computed a
  # CSP nonce, and calling request.content_security_policy_nonce
  # there can raise or hang on configuration paths that assume a real
  # request lifecycle. Returning nil makes downstream HTML emit
  # <script> tags without a nonce attribute — which is correct for
  # the static path because the static server doesn't issue a CSP
  # header to enforce against, so absent nonces are silently allowed.
  def safe_csp_nonce
    return nil if @static_generation
    return nil unless defined?(request) && request.respond_to?(:content_security_policy_nonce)
    request.content_security_policy_nonce
  rescue StandardError => e
    Rails.logger.debug "[ApplicationHelper] safe_csp_nonce returned nil: #{e.class}: #{e.message}"
    nil
  end

  def safe_system_image_path(filename, **options)
    return nil if filename.blank?
    system_image_path(filename, **options)
  rescue ActionController::UrlGenerationError
    nil
  end

  # Resolve a config-stored image reference (logo, favicon, podcast artwork,
  # …) to a usable URL. These fields historically held a bare filename served
  # from /site/system/assets/images via /system/images/<name>. They may now
  # also hold an absolute path — e.g. /media/images/logo.svg uploaded through
  # the main Media browser — or a full URL, which is used as-is. This lets an
  # image uploaded to /media work in config without moving it into the
  # global-images folder. Returns nil for blank / "none".
  def config_image_path(value, **options)
    v = value.to_s.strip
    return nil if v.empty? || v == "none"
    return v if v.start_with?("http://", "https://", "/")

    safe_system_image_path(v, **options)
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

  # Feature flag predicates — delegated to SiteFeature so models can use
  # the same checks without pulling in the helper context.
  def members_enabled?            = SiteFeature.members_enabled?
  def payments_enabled?           = SiteFeature.payments_enabled?
  def memberships_enabled?        = SiteFeature.memberships_enabled?
  def donations_enabled?          = SiteFeature.donations_enabled?
  def newsletters_enabled?        = SiteFeature.newsletters_enabled?
  def postmark_configured?        = SiteFeature.postmark_configured?
  def store_enabled?              = SiteFeature.store_enabled?
  def integrations_to_enable?     = SiteFeature.integrations_to_enable?
  def stripe_configured?          = SiteFeature.stripe_configured?
  def snipcart_configured?        = SiteFeature.snipcart_configured?
  def podcast_enabled?            = SiteFeature.podcast_enabled?
  def payments_feature_enabled?    = SiteFeature.payments_feature_enabled?
  def newsletters_feature_enabled? = SiteFeature.newsletters_feature_enabled?
  def any_integration_unconfigured? = SiteFeature.any_integration_unconfigured?
  def payments_unconfigured?       = SiteFeature.payments_unconfigured?
  def newsletters_unconfigured?    = SiteFeature.newsletters_unconfigured?
  def snipcart_unconfigured?       = SiteFeature.snipcart_unconfigured?

  def snipcart_connected?
    store_enabled? && SnipcartConfig.current&.connected?
  end

  # Audience only matters when paid memberships are actually configured —
  # without memberships, there's no "paid only" tier to gate on. (Donations
  # don't grant any tier, so they don't make audience meaningful.)
  def requires_audience_on_publish?
    memberships_enabled?
  end

  # Distribution prompt fires when newsletters are enabled. Postmark
  # config is checked separately as a soft warning inside the modal so
  # the user can still set published_to even if Postmark isn't ready.
  def requires_published_to_on_publish?
    newsletters_enabled?
  end

  def store_currency_symbol
    currency = SiteConfig.feature("store", "currency") || "usd"
    case currency.downcase
    when "usd" then "$"
    when "eur" then "€"
    when "gbp" then "£"
    when "cad" then "CA$"
    when "aud" then "A$"
    when "jpy" then "¥"
    else currency.upcase
    end
  end

  def product_breadcrumbs(product)
    return "" unless product
    return "" if product.metadata["breadcrumbs"] == false

    crumbs = []

    # Home
    crumbs << link_to("Home", "/", class: "breadcrumb-link")

    # Store
    store_page = Page.find_by("metadata->>'url_name' = ?", "store")
    if store_page
      crumbs << link_to("Store", "/store", class: "breadcrumb-link")
    else
      crumbs << content_tag(:span, "Store", class: "breadcrumb-text")
    end

    # Category (if exists)
    if product.metadata["category"].present?
      category = product.metadata["category"]
      category_page = Page.find_by("metadata->>'url_name' = ?", "store/#{category.parameterize}")

      if category_page
        crumbs << link_to(category.titleize, "/store/#{category.parameterize}", class: "breadcrumb-link")
      else
        crumbs << content_tag(:span, category.titleize, class: "breadcrumb-text")
      end
    end

    # Current product (not linked)
    crumbs << content_tag(:span, product.title, class: "breadcrumb-current")

    content_tag(:nav, crumbs.join(" › ").html_safe, class: "breadcrumbs", 'aria-label': "Breadcrumb")
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

  # Render an SVG icon from app/assets/images/icons/
  def icon_svg(name, options = {})
    file_path = Rails.root.join("app", "assets", "images", "icons", "#{name}.svg")

    return "" unless File.exist?(file_path)

    svg_content = File.read(file_path)
    css_class = options[:class] || "w-5 h-5"

    # Parse the SVG and add the class to the svg element
    doc = Nokogiri::HTML::DocumentFragment.parse(svg_content)
    svg = doc.at_css("svg")

    if svg
      existing_class = svg["class"]
      svg["class"] = existing_class ? "#{existing_class} #{css_class}" : css_class
      doc.to_html.html_safe
    else
      svg_content.html_safe
    end
  end
end
