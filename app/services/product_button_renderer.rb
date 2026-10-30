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

    items = products.map do |product|
      variant_name = product.variant || product.title
      button = render_button(product, text, style, 1, in_variant_list: true)

      "<li class=\"product-variant-item\">" \
      "<span class=\"variant-name\">#{ERB::Util.html_escape(variant_name)}</span> " \
      "#{variant_price_html(product)}" \
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
    Product.find_by("metadata->>'sku' = ?", sku) ||
      # Without Snipcart a product needn't have a SKU, so the block can name it
      # the way a product-link card does: by url_name.
      Product.all.find { |p| p.url_name == sku.to_s }
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
    button = render_button(product, text, style, quantity)

    # A single product's price is otherwise invisible — it rides along as
    # data-item-price for Snipcart, but nothing renders it. Shown by default
    # (a shopper expects a price next to a buy button); `show_price: false`
    # turns it off. Variant lists print their own, so this is the single case.
    # Not shown when the product sets no price — without Snipcart it needn't,
    # and "$0.00" would be wrong.
    return button if falsy?(config["show_price"]) || !price_set?(product)

    price = "#{get_currency_symbol}#{sprintf('%.2f', product.price)}"
    "<span class=\"product-price\">#{ERB::Util.html_escape(price)}</span> #{button}"
  end

  def price_set?(product)
    product.metadata["price"].to_s.strip.present?
  end

  # A variant's price cell. Always there, even empty: a variant list lays its
  # rows out on a grid, three cells each, and a missing one shifts the rest.
  def variant_price_html(product)
    price = price_set?(product) ? "#{get_currency_symbol}#{sprintf('%.2f', product.price)}" : ""
    "<span class=\"variant-price\">#{price}</span> "
  end

  # Block values arrive as real booleans from YAML or as strings from the
  # builder, so accept both. Anything unset means "default", i.e. show.
  def falsy?(value)
    %w[false no 0].include?(value.to_s.strip.downcase)
  end

  def render_product_list(products)
    # Build variant list
    text = config["text"] || "Add to Cart"
    style = config["style"] || "primary"

    items = products.map do |product|
      variant_name = product.respond_to?(:variant) && product.variant.present? ? product.variant : product.title
      button = render_button(product, text, style, 1, in_variant_list: true)

      "<li class=\"product-variant-item\">" \
      "<span class=\"variant-name\">#{ERB::Util.html_escape(variant_name)}</span> " \
      "#{variant_price_html(product)}" \
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

  def render_button(product, text, style, quantity, in_variant_list: false)
    # Without Snipcart there's no cart to add to. A button elsewhere (a post
    # pointing at a book) becomes a link to the product's page, where its
    # store links live. On the product's own page it would only link to
    # itself, so nothing renders.
    unless SiteFeature.snipcart_enabled?
      # In a variant list every row is three cells — name, price, button — on
      # a grid, so a row with no button shifts everything after it. The
      # product you're already on gets a marker in that cell instead.
      if context[:current_product]&.id == product.id
        return in_variant_list ? %(<span class="variant-current"></span>) : ""
      end

      # A template's "Add to Cart" (the default product template writes it)
      # is the wrong label on a link; it falls back to "View" like the rest.
      label = config["text"].to_s.strip
      label = "View" if label.empty? || label.casecmp?("add to cart")
      return %(<a href="#{ERB::Util.html_escape(product.public_url)}" class="btn-#{ERB::Util.html_escape(style)}">#{ERB::Util.html_escape(label)}</a>)
    end

    # No button for a digital product that can't deliver — see
    # Product#deliverable?. A missing GUID is the dangerous case: Snipcart
    # accepts the order and has nothing to send.
    return render_undeliverable(product) unless product.deliverable?

    # Get the domain for Snipcart validation
    domain = SiteConfig.feature("store", "default_domain")

    validation_url = if domain.present?
      # Remove protocol prefix and trailing slashes
      clean_domain = domain.to_s.sub(/\Ahttps?:\/\//, "").sub(/\/+\z/, "")
      "https://#{clean_domain}/store/#{product.url_name}"
    else
      "/store/#{product.url_name}"
    end

    # Product#snipcart_attributes is the one place that decides what Snipcart
    # gets, so a digital good's file GUID and shippable flag reach every button
    # rather than only the ones someone remembered to update.
    attrs = product.snipcart_attributes(url: validation_url, quantity: quantity)

    attr_string = attrs.map { |k, v| "#{k}=\"#{ERB::Util.html_escape(v)}\"" }.join(" ")

    <<~HTML.strip
      <button class="snipcart-add-item btn-#{ERB::Util.html_escape(style)}"
              data-turbo="false"
              #{attr_string}>
        #{ERB::Util.html_escape(text)}
      </button>
    HTML
  end

  def render_undeliverable(product)
    reason = product.delivery_problem == :missing_file_guid ?
      "has no Snipcart file GUID" : "has a malformed Snipcart file GUID"

    <<~HTML.strip
      <div class="product-button-error" style="padding: 1rem; background: #fef2f2; border: 1px solid #fecaca; color: #991b1b; border-radius: 0.25rem;">
        <strong>Not available to buy.</strong> This digital product #{reason}, so it can't be sold yet.
      </div>
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
