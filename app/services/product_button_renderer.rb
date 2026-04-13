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
    # Auto-detect product on product pages if no SKU provided
    product = if config['sku'].present?
                Product.find_by("metadata->>'sku' = ?", config['sku'])
              elsif context[:current_product]
                context[:current_product]
              else
                nil
              end

    # Handle missing product
    unless product
      return render_error if context[:authenticated]
      return '' # Hide for public users
    end

    # Validate product is published (unless admin)
    unless product.status == 'published' || context[:authenticated]
      return render_error('Product not published') if context[:authenticated]
      return ''
    end

    # Build button attributes
    text = config['text'] || 'Add to Cart'
    style = config['style'] || 'primary'
    quantity = config['quantity']&.to_i || 1

    # Generate Snipcart button
    render_button(product, text, style, quantity)
  end

  private

  def render_button(product, text, style, quantity)
    attrs = product.snipcart_attributes.merge({
      'data-item-quantity' => quantity
    })

    attr_string = attrs.map { |k, v| "#{k}=\"#{ERB::Util.html_escape(v)}\"" }.join(' ')

    <<~HTML.strip
      <button class="snipcart-add-item button-#{ERB::Util.html_escape(style)}" #{attr_string}>
        #{ERB::Util.html_escape(text)}
      </button>
    HTML
  end

  def render_error(message = 'Product not found')
    sku = config['sku'] || 'unknown'
    <<~HTML.strip
      <div class="product-button-error" style="padding: 1rem; background: #fef2f2; border: 1px solid #fecaca; color: #991b1b; border-radius: 0.25rem;">
        <strong>Button Error:</strong> #{ERB::Util.html_escape(message)}
        <br><small>SKU: #{ERB::Util.html_escape(sku)}</small>
      </div>
    HTML
  end
end
