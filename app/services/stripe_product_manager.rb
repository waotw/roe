class StripeProductManager
  attr_reader :stripe_config, :errors

  def initialize
    @stripe_config = StripeConfig.current
    @errors = []
  end

  # Create or update product/price based on config
  def sync_from_config(payments_config)
    return false unless validate_config(payments_config)
    return false unless stripe_config.connected?

    price_amount = parse_price(payments_config['price'])
    return false if price_amount.nil?

    # Ensure product exists
    product = ensure_product_exists!
    return false unless product

    # Create new price (Stripe best practice: create new, don't update)
    price = create_price!(product.id, price_amount)
    return false unless price

    # Update StripeConfig with IDs
    stripe_config.update!(
      product_id: product.id,
      price_id: price.id
    )

    true
  rescue Stripe::StripeError => e
    @errors << "Stripe API error: #{e.message}"
    Rails.logger.error "StripeProductManager error: #{e.message}"
    false
  end

  private

  def validate_config(config)
    unless config['enabled'] == true || config['enabled'] == 'true'
      @errors << "Payments not enabled"
      return false
    end

    unless config['price'].present?
      @errors << "Price not set"
      return false
    end

    true
  end

  def parse_price(price_string)
    # Convert "49.00" to 4900 (cents)
    amount = Float(price_string) * 100
    amount.to_i
  rescue ArgumentError
    @errors << "Invalid price format"
    nil
  end

  def ensure_product_exists!
    # If we already have a product_id, retrieve it
    if stripe_config.product_id.present?
      begin
        return Stripe::Product.retrieve(stripe_config.product_id, request_options)
      rescue Stripe::InvalidRequestError
        # Product was deleted, create a new one
        Rails.logger.warn "Stripe product not found, creating new one"
      end
    end

    # Create new product
    site_title = SiteConfig.get('title') || 'My Site'

    Stripe::Product.create(
      {
        name: "Paid Membership",
        description: "Access to paid content on #{site_title}",
        metadata: {
          roe_cms: true,
          site: site_title
        }
      },
      request_options
    )
  end

  def create_price!(product_id, amount_cents)
    Stripe::Price.create(
      {
        product: product_id,
        unit_amount: amount_cents,
        currency: stripe_config.default_currency,
        metadata: {
          roe_cms: true
        }
      },
      request_options
    )
  end

  def request_options
    { api_key: stripe_config.current_secret_key }
  end
end
