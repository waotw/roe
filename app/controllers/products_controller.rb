class ProductsController < SiteController
  def show
    # A variant group shares one url_name across its members; the group's
    # page is the primary variant's (its content, gallery, etc.), so prefer
    # it. Ungrouped products have a single match, so first == the product.
    matches = Product.where("metadata->>'url_name' = ?", params[:url_name])
    @product = matches.detect(&:primary?) || matches.first

    # An old /store/<name> address whose product has since been renamed:
    # on to /products/<name>, where a rename's redirect (RenameRedirect)
    # takes it the rest of the way.
    # The breadcrumbs before 0.5.1 linked a category to /store/<category>.
    if !@product && request.path.start_with?("/store/")
      category = StorePages.category_for_slug(params[:url_name])
      target = category ? StorePages.category_url(category) : Product.public_url_for(params[:url_name])
      return redirect_to target, status: :moved_permanently
    end

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

  # /products/category/<category>: the category's page when it has one
  # (`category:` on a page), else Roe's listing of its products.
  def category
    name = StorePages.category_for_slug(params[:category])
    raise ActiveRecord::RecordNotFound unless name

    if (page = StorePages.category_page(name))
      return redirect_to page.public_url, status: :moved_permanently
    end

    @page = StorePages.listing_page(name)
    render "pages/show"
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
      "#{protocol}://#{clean_domain}#{product.public_url}.json"
    else
      # Development: use request base URL
      "#{request.base_url}#{product.public_url}.json"
    end
  end
end
