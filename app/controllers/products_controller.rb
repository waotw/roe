class ProductsController < SiteController
  def show
    # A variant group shares one url_name across its members; the group's
    # page is the primary variant's (its content, gallery, etc.), so prefer
    # it. Ungrouped products have a single match, so first == the product.
    matches = Product.where("metadata->>'url_name' = ?", params[:url_name])
    @product = matches.detect(&:primary?) || matches.first

    # Raise 404 if not found
    raise ActiveRecord::RecordNotFound unless @product

    # Only show published products to non-admins
    unless @product.status == "published" || authenticated?
      raise ActiveRecord::RecordNotFound
    end

    respond_to do |format|
      format.html # Render the normal product page
      format.json do
        # Snipcart validation response
        render json: {
          id: @product.sku,
          price: @product.price.to_f,
          url: product_url_for_validation(@product)
        }
      end
    end
  end

  private

  def product_url_for_validation(product)
    # Use the full URL for Snipcart validation
    if Rails.env.production?
      # Use configured domain from store.yml
      domain = SiteConfig.feature("store", "default_domain") || request.host

      # Remove protocol prefix and trailing slashes
      clean_domain = domain.to_s.sub(/\Ahttps?:\/\//, "").sub(/\/+\z/, "")

      protocol = clean_domain.include?("localhost") ? "http" : "https"
      "#{protocol}://#{clean_domain}/store/#{product.url_name}.json"
    else
      # Development: use request base URL
      "#{request.base_url}/store/#{product.url_name}.json"
    end
  end
end
