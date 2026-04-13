class ProductsController < SiteController
  def show
    @product = Product.find_by("metadata->>'url_name' = ?", params[:url_name])

    # Raise 404 if not found
    raise ActiveRecord::RecordNotFound unless @product

    # Only show published products to non-admins
    unless @product.status == 'published' || authenticated?
      raise ActiveRecord::RecordNotFound
    end

    # Handle Snipcart validation requests
    if request.headers['User-Agent']&.include?('Snipcart') ||
       request.headers['HTTP_X_SNIPCART_REQUESTTOKEN'].present?

      Rails.logger.info "Snipcart validation request for: #{@product.url_name}"

      response_data = {
        id: @product.sku,
        price: @product.price.to_f,
        url: product_url(@product.url_name),
        name: @product.title,
        description: @product.description || ''
      }

      Rails.logger.info "Snipcart validation response: #{response_data.inspect}"

      render json: response_data
      return
    end

    # Normal page view - layout is set by SiteController
  end

  private

  def product_url(url_name)
    "#{request.base_url}/store/#{url_name}"
  end
end
