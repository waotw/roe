class Admin::ProductsController < Admin::BaseController
  layout -> { action_name == "edit" ? "editor" : "admin" }

  before_action :set_product, only: [ :edit, :update, :show, :destroy ]

  def index
    # Ordered "rows" for the table: each is either a bare Product (standalone)
    # or a ProductGroup (2+ products sharing a `group:` value), most-recently-
    # edited first, groups kept together with their primary on top. Grouping is
    # derived from front-matter, not stored — see ProductGroup.
    @rows = ProductGroup.rows_for(Product.all)
  end

  def new
    @template = ContentTemplate.template_content("product")
  end

  def create
    filename = sanitize_filename(params[:filename])

    # Ensure products directory exists
    products_dir = Pathname.new(File.join(RoeSitePaths::SITE_PATH, "products"))
    FileUtils.mkdir_p(products_dir) unless Dir.exist?(products_dir)

    file_path = products_dir.join("#{filename}.md")

    if File.exist?(file_path)
      flash.now[:error] = "A product with that filename already exists"
      @template = params[:content]
      @filename = filename
      render :new, status: :unprocessable_entity
      return
    end

    title = filename_to_title(filename)
    metadata, body = ContentTemplate.frontmatter_for("product", "title" => title, "url_name" => filename)

    yaml_content = metadata.to_yaml.sub(/\A---\n/, "")
    content = "---\n#{yaml_content}\n---\n#{body}"

    File.write(file_path, content)
    ContentSync.sync_file(file_path)

    relative_path = file_path.to_s.sub(RoeSitePaths::SITE_PATH.to_s + "/", "")
    product = Product.find_by(file_path: relative_path)

    if product
      redirect_to edit_admin_product_path(product), notice: "Product created"
    else
      flash[:error] = "Product file created but failed to sync to database"
      redirect_to admin_products_path
    end
  end

  def edit
    @product = Product.find(params[:id])
    raw_content = File.read(File.join(RoeSitePaths::SITE_PATH, @product.file_path))

    begin
      parsed = FrontMatterParser::Parser.new(:md).call(raw_content)
      @metadata = parsed.front_matter.to_yaml.sub(/\A---\n/, "")
      @content = parsed.content
    rescue => e
      flash.now[:error] = "Error parsing product file: #{e.message}"
      @metadata = ""
      @content = raw_content
    end

    @preview_path = preview_admin_product_path(@product)
  end

  def update
    @product = Product.find(params[:id])

    metadata_yaml = params[:metadata_final].presence || params[:metadata]

    begin
      metadata = YAML.safe_load(metadata_yaml, permitted_classes: [ Date, Time, Symbol ])

      unless metadata.is_a?(Hash)
        raise "Metadata must be key-value pairs"
      end

      # Handle tags
      if metadata["tags"].is_a?(String)
        if metadata["tags"].strip.empty? || metadata["tags"] == "[]"
          metadata["tags"] = []
        else
          metadata["tags"] = metadata["tags"].split(",").map(&:strip).reject(&:empty?)
        end
      elsif metadata["tags"].nil?
        metadata["tags"] = []
      end

      yaml_content = Product.format_metadata_yaml(metadata)

    rescue => e
      flash[:warning] = "YAML warning: #{e.message}. File saved anyway."
      full_content = "---\n#{metadata_yaml}\n---\n#{params[:content]}"
      File.write(File.join(RoeSitePaths::SITE_PATH, @product.file_path), full_content)
      redirect_to edit_admin_product_path(@product)
      return
    end

    # Capture pre-save state to detect a publishing transition for flash text.
    was_published = @product.status == "published"

    full_content = "---\n#{yaml_content}\n---\n#{params[:content]}"
    File.write(File.join(RoeSitePaths::SITE_PATH, @product.file_path), full_content)

    ContentSync.sync_file(File.join(RoeSitePaths::SITE_PATH, @product.file_path))
    @product.reload

    flash[:notice] = (!was_published && @product.status == "published") ? "Product published" : "Product saved"
    redirect_to edit_admin_product_path(@product)
  end

  def show
    @product = Product.find(params[:id])

    respond_to do |format|
      format.json do
        render json: {
          id: @product.id,
          title: @product.title,
          sku: @product.sku,
          price: @product.price,
          image: @product.image,
          description: @product.description,
          url_name: @product.url_name
        }
      end
    end
  end

  def search
    query = params[:query].to_s.downcase
    matched = Product.published
                     .select { |p| p.title.to_s.downcase.include?(query) }
                     .first(40)

    # Group variants under their primary (mirrors the product index): primary
    # first, then variants (flagged for indenting), then standalone products.
    # The typeahead links either the group's primary or a specific variant.
    results = []
    ProductGroup.rows_for(matched).each do |row|
      if row.is_a?(ProductGroup)
        row.ordered_members.each_with_index do |member, i|
          results << product_search_result(member, primary: member.primary?, indent: i.positive?)
        end
      else
        results << product_search_result(row, primary: false, indent: false)
      end
    end

    render json: results.first(20)
  end

  def product_search_result(product, primary:, indent:)
    {
      id: product.id,
      title: product.title,
      url_name: product.url_name,
      price: product.price,
      variant: product.variant,
      primary: primary,
      indent: indent
    }
  end
  private :product_search_result

  # Copy a product's file into a numbered sibling — "-N" on the filename, " N"
  # on the title (from 2, skipping any that exist). Product file_paths are
  # relative, so every File op joins SITE_PATH. Redirects into the new copy.
  def duplicate
    @product = Product.find(params[:id])
    parsed = FrontMatterParser::Parser.new(:md).call(File.read(File.join(RoeSitePaths::SITE_PATH, @product.file_path)))
    metadata = parsed.front_matter

    rel_dir = File.dirname(@product.file_path)
    base_name = File.basename(@product.file_path, ".md").sub(/-\d+\z/, "")
    base_title = metadata["title"].to_s.sub(/\s+\d+\z/, "").strip

    n = 2
    n += 1 while File.exist?(File.join(RoeSitePaths::SITE_PATH, rel_dir, "#{base_name}-#{n}.md"))
    new_rel = File.join(rel_dir, "#{base_name}-#{n}.md")

    metadata["title"] = base_title.present? ? "#{base_title} #{n}" : "Untitled #{n}"
    File.write(File.join(RoeSitePaths::SITE_PATH, new_rel),
               "---\n#{Product.format_metadata_yaml(metadata)}\n---\n#{parsed.content}")
    ContentSync.sync_file(File.join(RoeSitePaths::SITE_PATH, new_rel))

    new_product = Product.find_by(file_path: new_rel)
    if new_product
      redirect_to edit_admin_product_path(new_product), notice: "Product duplicated"
    else
      redirect_to admin_products_path, alert: "Duplicated the file but couldn't load the new product."
    end
  end

  def rename
    @product = Product.find(params[:id])
    new_filename = sanitize_filename(params[:new_filename])

    # Return to wherever rename was submitted from (editor/index); only same-site
    # absolute paths are honored.
    return_to = lambda do
      target = params[:return_to].to_s
      safe = target.start_with?("/") && !target.start_with?("//")
      redirect_to(safe ? target : admin_products_path, allow_other_host: false)
    end

    if new_filename.blank?
      flash[:error] = "Filename cannot be empty"
      return_to.call and return
    end

    old_rel = @product.file_path
    new_rel = File.join(File.dirname(old_rel), "#{new_filename}.md")
    old_full = File.join(RoeSitePaths::SITE_PATH, old_rel)
    new_full = File.join(RoeSitePaths::SITE_PATH, new_rel)

    if File.exist?(new_full) && new_full != old_full
      flash[:error] = "A file with that name already exists"
      return_to.call and return
    end

    begin
      File.rename(old_full, new_full)
      @product.update(file_path: new_rel)
      ContentSync.sync_file(new_full)
      flash[:notice] = "Renamed to #{new_filename}.md"
    rescue => e
      flash[:error] = "Failed to rename: #{e.message}"
    end

    return_to.call
  end

  def destroy
    @product = Product.find(params[:id])
    file_path = File.join(RoeSitePaths::SITE_PATH, @product.file_path)

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
        metadata = YAML.safe_load(metadata_yaml, permitted_classes: [ Date, Time, Symbol ]) || {}
      rescue
        metadata = {}
      end

      # Preserve url_name from database if not in submitted metadata
      metadata["url_name"] ||= @product.metadata["url_name"]

      @product.metadata = metadata
      @product.content = content
    end
    # GET = show saved version from database

    # ALWAYS set preview mode
    @preview_mode = true
    @preview_id = "product-#{@product.id}"

    render template: "products/show", layout: "site"
  end

  def publish_modal
    @product = Product.find(params[:id])

    # Swap in submitted form-state metadata so the modal reflects what's
    # *about to be saved* — same pattern as posts/pages.
    if params[:metadata].present?
      begin
        submitted = YAML.safe_load(params[:metadata], permitted_classes: [ Date, Time, Symbol ])
        @product.metadata = submitted if submitted.is_a?(Hash) && submitted.any?
      rescue => e
        Rails.logger.warn "publish_modal: ignoring unparseable submitted metadata (#{e.message})"
      end
    end

    @missing_requirements = build_publish_requirements(@product)
    # Required fields that are already set — shown as read-only "✓" confirmation
    # bullets. The metadata editor is the source of truth, so the modal just
    # reflects it: present → confirm, missing → fill in.
    @present_requirements = Product::REQUIRED_FIELDS
      .select { |name| @product.metadata[name].to_s.strip.present? }
      .map { |name| { name: name, label: name.humanize, value: @product.metadata[name] } }
    @resource_label = "Product"
    @show_postmark_warning = false  # products don't go to newsletter
    @paired_duration_for = nil       # no audio/video pairing for products
    @sku_generator_path = sku_generator_admin_product_path(@product)

    render partial: "admin/posts/publish_modal", layout: false
  end

  def unpublish
    @product = Product.find(params[:id])
    @product.metadata["status"] = "draft"
    save_product_to_file(@product)

    flash[:notice] = "Product unpublished"
    redirect_to edit_admin_product_path(@product)
  end

  def sku_generator
    @product = Product.find(params[:id])

    # Get current metadata values
    @title = @product.title
    @category = @product.metadata["category"]

    render partial: "sku_generator_modal", locals: { product: @product }
  end

  def next_sku_number
    category = params[:category] || "PROD"
    next_number = Product.next_number_for_category(category)
    render json: { next_number: next_number }
  end

  def check_sku
    sku = params[:sku]
    exists = Product.sku_exists?(sku)
    render json: { exists: exists }
  end

  def duplicate_skus
    @duplicates = Product.duplicate_skus
  end

  private

  # Builds the sections shown in the publish modal — same shape as the
  # posts version. Products gate on their REQUIRED_FIELDS plus any
  # broken media path.
  def build_publish_requirements(product)
    hints = {
      "title"    => "Product title",
      "category" => begin
        cats = ProductCategory.all rescue []
        cats.any? ? "e.g., #{cats.first(3).join(', ')}" : "e.g., book, ebook, poster"
      end,
      "price"    => "Price in dollars (e.g., 29.99)",
      "sku"      => "Stock Keeping Unit (e.g., BOOK-001-TITLE)",
      "image"    => "Path to product image: /media/images/file.jpg"
    }

    requirements = product.missing_required_fields.map do |name|
      {
        name: name,
        type: :text,
        label: name.humanize,
        hint: hints[name],
        current: product.metadata[name]
      }
    end

    # Add broken-media-path entries for fields that already have a value
    # set (so they wouldn't be in missing_required_fields).
    already_listed = requirements.map { |r| r[:name] }
    product.missing_media_refs.each do |ref|
      next if already_listed.include?(ref[:field])
      requirements << {
        name: ref[:field],
        type: :text,
        label: ref[:field].humanize,
        hint: "File not found on disk — fix the path or upload the file.",
        current: ref[:path],
        missing_file: true
      }
    end

    # Generating a SKU requires picking a category, and that category becomes the
    # product's category on publish — so don't ask for it separately while the
    # SKU is still missing. (When only the category is missing it stays.)
    if requirements.any? { |r| r[:name] == "sku" }
      requirements.reject! { |r| r[:name] == "category" }
    end

    requirements
  end

  def save_product_to_file(product)
    yaml_content = product.metadata.to_yaml.sub(/\A---\n/, "")
    full_content = "---\n#{yaml_content}\n---\n#{product.content}"
    File.write(File.join(RoeSitePaths::SITE_PATH, product.file_path), full_content)
    ContentSync.sync_file(File.join(RoeSitePaths::SITE_PATH, product.file_path))
  end

  def set_product
    @product = Product.find(params[:id])
  end

  def sanitize_filename(filename)
    filename.parameterize
  end

  def filename_to_title(filename)
    filename.gsub("-", " ").titleize
  end

  def load_product_template
    template_path = File.join(RoeSitePaths::SITE_PATH, "system", "templates", "product_template.md")

    if File.exist?(template_path)
      File.read(template_path)
    else
      # Default template
      <<~MARKDOWN
        ---
        title:
        url_name:
        category:
        status: draft
        price: 0.00
        sku:
        image:
        description:
        tags: []
        group:
        primary: false
        variant:
        ---

        Product description goes here...
      MARKDOWN
    end
  end
end
