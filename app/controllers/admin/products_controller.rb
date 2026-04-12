class Admin::ProductsController < Admin::BaseController
  before_action :set_product, only: [:edit, :update, :destroy]

  def index
    @products = Product.by_newest
  end

  def new
    @template = load_product_template
  end

  def create
    filename = sanitize_filename(params[:filename])

    # Ensure products directory exists
    products_dir = Rails.root.join("site/products")
    FileUtils.mkdir_p(products_dir) unless Dir.exist?(products_dir)

    file_path = products_dir.join("#{filename}.md")

    if File.exist?(file_path)
      flash.now[:error] = "A product with that filename already exists"
      @template = params[:content]
      @filename = filename
      render :new, status: :unprocessable_entity
      return
    end

    template_content = load_product_template
    title = filename_to_title(filename)

    parsed = FrontMatterParser::Parser.new(:md).call(template_content)
    metadata = parsed.front_matter.merge(
      "title" => title,
      "url_name" => filename
    )

    yaml_content = metadata.to_yaml.sub(/\A---\n/, '')
    content = "---\n#{yaml_content}\n---\n#{parsed.content}"

    File.write(file_path, content)
    ContentSync.sync_file(file_path)

    product = Product.find_by(file_path: file_path.to_s.sub(Rails.root.to_s + "/", ""))

    if product
      redirect_to edit_admin_product_path(product), notice: "Product created"
    else
      flash[:error] = "Product file created but failed to sync to database"
      redirect_to admin_products_path
    end
  end

  def edit
    @product = Product.find(params[:id])
    raw_content = File.read(Rails.root.join(@product.file_path))

    begin
      parsed = FrontMatterParser::Parser.new(:md).call(raw_content)
      @metadata = parsed.front_matter.to_yaml.sub(/\A---\n/, '')
      @content = parsed.content
    rescue => e
      flash.now[:error] = "Error parsing product file: #{e.message}"
      @metadata = ""
      @content = raw_content
    end
  end

  def update
    @product = Product.find(params[:id])

    metadata_yaml = params[:metadata_final].presence || params[:metadata]

    begin
      metadata = YAML.safe_load(metadata_yaml, permitted_classes: [Date, Time, Symbol])

      unless metadata.is_a?(Hash)
        raise "Metadata must be key-value pairs"
      end

      # Handle tags
      if metadata['tags'].is_a?(String)
        if metadata['tags'].strip.empty? || metadata['tags'] == '[]'
          metadata['tags'] = []
        else
          metadata['tags'] = metadata['tags'].split(',').map(&:strip).reject(&:empty?)
        end
      elsif metadata['tags'].nil?
        metadata['tags'] = []
      end

      yaml_content = metadata.to_yaml.sub(/\A---\n/, '')

    rescue => e
      flash[:warning] = "YAML warning: #{e.message}. File saved anyway."
      full_content = "---\n#{metadata_yaml}\n---\n#{params[:content]}"
      File.write(Rails.root.join(@product.file_path), full_content)
      redirect_to edit_admin_product_path(@product)
      return
    end

    full_content = "---\n#{yaml_content}\n---\n#{params[:content]}"
    File.write(Rails.root.join(@product.file_path), full_content)

    ContentSync.sync_file(Rails.root.join(@product.file_path))

    flash[:notice] = "Product saved"
    redirect_to edit_admin_product_path(@product)
  end

  def destroy
    @product = Product.find(params[:id])
    file_path = Rails.root.join(@product.file_path)

    File.delete(file_path) if File.exist?(file_path)
    @product.destroy

    flash[:notice] = "Product deleted successfully"
    redirect_to admin_products_path
  end

  def preview
    @product = Product.find(params[:id])

    # POST = live editing preview with unsaved content
    if request.post?
      metadata_yaml = params[:metadata]
      content = params[:content]

      begin
        metadata = YAML.safe_load(metadata_yaml, permitted_classes: [Date, Time, Symbol]) || {}
      rescue
        metadata = {}
      end

      # Preserve url_name from database if not in submitted metadata
      metadata['url_name'] ||= @product.metadata['url_name']

      @product.metadata = metadata
      @product.content = content
    end
    # GET = show saved version from database

    # ALWAYS set preview mode
    @preview_mode = true
    @preview_id = "product-#{@product.id}"

    render template: 'products/show', layout: 'site'
  end

  def publish_modal
    @product = Product.find(params[:id])
    @missing_sku = @product.sku.blank?
    render partial: 'publish_modal', layout: false
  end

  def confirm_publish
    @product = Product.find(params[:id])

    # If SKU was provided in the form, update it
    if params[:sku].present?
      @product.metadata['sku'] = params[:sku]
    end

    # Check if SKU is present (either from before or just added)
    if @product.sku.blank?
      flash[:error] = 'SKU is required to publish'
      redirect_to edit_admin_product_path(@product)
      return
    end

    @product.metadata['status'] = 'published'
    save_product_to_file(@product)

    flash[:notice] = 'Product published successfully'
    redirect_to edit_admin_product_path(@product)
  end

  def publish
    # This is now just a redirect to unpublish (for the button)
    # The actual publishing happens via the modal
    redirect_to edit_admin_product_path(params[:id])
  end

  def unpublish
    @product = Product.find(params[:id])
    @product.metadata['status'] = 'draft'
    save_product_to_file(@product)

    flash[:notice] = 'Product unpublished'
    redirect_to edit_admin_product_path(@product)
  end

  def check_sku
    sku = params[:sku]
    exists = Product.sku_exists?(sku)
    render json: { exists: exists }
  end

  private

  def save_product_to_file(product)
    yaml_content = product.metadata.to_yaml.sub(/\A---\n/, '')
    full_content = "---\n#{yaml_content}\n---\n#{product.content}"
    File.write(Rails.root.join(product.file_path), full_content)
    ContentSync.sync_file(Rails.root.join(product.file_path))
  end

  private

  def set_product
    @product = Product.find(params[:id])
  end

  def sanitize_filename(filename)
    filename.parameterize
  end

  def filename_to_title(filename)
    filename.gsub('-', ' ').titleize
  end

  def load_product_template
    template_path = Rails.root.join('site', 'system', 'templates', 'product_template.md')

    if File.exist?(template_path)
      File.read(template_path)
    else
      # Default template
      <<~MARKDOWN
        ---
        title:
        url_name:
        status: draft
        price: 0.00
        sku:
        image:
        description:
        tags: []
        ---

        Product description goes here...
      MARKDOWN
    end
  end
end
