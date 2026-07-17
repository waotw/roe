# app/services/product_button_renderer.rb
class ProductButtonRenderer
  attr_reader :config, :context

  def initialize(config, context = {})
    @config = config
    @context = context
  end

  def self.render(config, context = {})
    new(config, context).render
  end

  def render
    # Check if we have multiple SKUs (variants)
    skus = extract_skus

    if skus.length > 1
      # Render as variant list
      render_variant_list(skus)
    elsif skus.length == 1
      # Single product button
      product = find_product(skus.first)
      render_single_product(product)
    else
      # Auto-detect product on product pages if no SKU provided
      product = context[:current_product]
      render_single_product(product)
    end
  end

  def render_variant_list(skus = nil)
    skus ||= config["skus"] || []
    skus = Array(skus)

    return "" if skus.empty?

    # Find all products
    products = skus.map { |sku| find_product(sku) }.compact

    # Filter to only published products for public users
    unless context[:authenticated]
      products = products.select { |p| p.status == "published" }
    end

    return "" if products.empty?
    return render_single_product(products.first) if products.length == 1

    # Build variant list
    text = config["text"] || "Add to Cart"
    style = config["style"] || "primary"
    currency = get_currency_symbol

    items = products.map do |product|
      variant_name = product.variant || product.title
      price = "#{currency}#{sprintf('%.2f', product.price)}"
      button = render_button(product, text, style, 1)

      "<li class=\"product-variant-item\">" \
      "<span class=\"variant-name\">#{ERB::Util.html_escape(variant_name)}</span> " \
      "<span class=\"variant-price\">#{price}</span> " \
      "#{button}" \
      "</li>"
    end

    "<ul class=\"product-variant-list\">\n#{items.join("\n")}\n</ul>"
  end

  private

  def extract_skus
    skus = []

    # Check for single SKU
    skus << config["sku"] if config["sku"].present?

    # Check for multiple SKUs in variants array
    if config["variants"].is_a?(Array)
      skus.concat(config["variants"].map { |v| v["sku"] || v }.compact)
    elsif config["variants"].is_a?(String)
      # Comma-separated SKUs
      skus.concat(config["variants"].split(",").map(&:strip))
    end

    skus.uniq
  end

  def find_product(sku)
    Product.find_by("metadata->>'sku' = ?", sku)
  end

  def render_single_product(product)
    # Handle missing product
    unless product
      return render_error if context[:authenticated]
      return "" # Hide for public users
    end

    # Validate product is published (unless admin)
    unless product.status == "published" || context[:authenticated]
      return render_error("Product not published") if context[:authenticated]
      return ""
    end

    # Check if product has variants (is part of a group)
    if product.respond_to?(:group) && product.group.present?
      # Find all products in this group
      group_products = Product.where("json_extract(metadata, '$.group') = ?", product.group).to_a

      # Filter to published products for public users
      unless context[:authenticated]
        group_products = group_products.select { |p| p.status == "published" }
      end

      # If there are multiple products in the group, render as variant list
      if group_products.length > 1
        # Sort: primary first, then by created_at
        sorted_products = group_products.sort_by do |p|
          primary = p.respond_to?(:primary?) && p.primary? ? 0 : 1
          [ primary, p.created_at ]
        end

        return render_product_list(sorted_products)
      end
    end

    # Build button attributes
    text = config["text"] || "Add to Cart"
    style = config["style"] || "primary"
    quantity = config["quantity"]&.to_i || 1

    # Generate Snipcart button
    render_button(product, text, style, quantity)
  end

  def render_product_list(products)
    # Build variant list
    text = config["text"] || "Add to Cart"
    style = config["style"] || "primary"
    currency = get_currency_symbol

    items = products.map do |product|
      variant_name = product.respond_to?(:variant) && product.variant.present? ? product.variant : product.title
      price = "#{currency}#{sprintf('%.2f', product.price)}"
      button = render_button(product, text, style, 1)

      "<li class=\"product-variant-item\">" \
      "<span class=\"variant-name\">#{ERB::Util.html_escape(variant_name)}</span> " \
      "<span class=\"variant-price\">#{price}</span> " \
      "#{button}" \
      "</li>"
    end

    "<ul class=\"product-variant-list\">\n#{items.join("\n")}\n</ul>"
  end

  def get_currency_symbol
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

  private

  def render_button(product, text, style, quantity)
    # Get the domain for Snipcart validation
    domain = SiteConfig.feature("store", "default_domain")

    validation_url = if domain.present?
      # Remove protocol prefix and trailing slashes
      clean_domain = domain.to_s.sub(/\Ahttps?:\/\//, "").sub(/\/+\z/, "")
      "https://#{clean_domain}/store/#{product.url_name}"
    else
      "/store/#{product.url_name}"
    end

    attrs = {
      "data-item-id" => product.sku,
      "data-item-name" => product.title,
      "data-item-price" => product.price,
      "data-item-url" => validation_url,
      "data-item-quantity" => quantity
    }

    # Add optional attributes
    attrs["data-item-description"] = product.description if product.description.present?
    attrs["data-item-image"] = product.image if product.image.present?

    attr_string = attrs.map { |k, v| "#{k}=\"#{ERB::Util.html_escape(v)}\"" }.join(" ")

    <<~HTML.strip
      <button class="snipcart-add-item btn-#{ERB::Util.html_escape(style)}"
              data-turbo="false"
              #{attr_string}>
        #{ERB::Util.html_escape(text)}
      </button>
    HTML
  end

  def render_error(message = "Product not found")
    sku = config["sku"] || "unknown"
    <<~HTML.strip
      <div class="product-button-error" style="padding: 1rem; background: #fef2f2; border: 1px solid #fecaca; color: #991b1b; border-radius: 0.25rem;">
        <strong>Button Error:</strong> #{ERB::Util.html_escape(message)}
        <br><small>SKU: #{ERB::Util.html_escape(sku)}</small>
      </div>
    HTML
  end
end
