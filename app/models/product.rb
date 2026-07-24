class Product < ApplicationRecord
  include HasMetadata
  include HasMarkdownExtensions
  include HasInlineFootnotes
  include TouchesMediaUsageIndex

  # Validations
  validates :file_path, presence: true, uniqueness: true

  # NOTE: no metadata-level validations. Roe is file-first — the file is
  # the source of truth, and a model-level validation here would silently
  # block ContentSync/ContentWatcher from updating the DB when a product
  # file is saved with missing fields, which makes the admin UI lie about
  # what's on disk. Required-field gating happens in the publish modal
  # before content goes live, and admin warning badges surface mistakes
  # via Product#needs_attention? after the fact.

  # Required metadata fields. Mirrored in the metadata editor partial's
  # `required: true` flags for product fields. Used by needs_attention?
  # to flag published products that are missing critical info.
  REQUIRED_FIELDS = %w[title category price sku image].freeze

  # Metadata fields that point at files under site/media/...
  MEDIA_FIELDS = %w[image].freeze

  after_save :register_category
  after_save :register_group

  # Scopes — SQLite uses json_extract, NOT the PostgreSQL `metadata->>'key'` syntax.
  scope :published, -> { where("json_extract(metadata, '$.status') = ?", "published") }
  scope :draft, -> { where("json_extract(metadata, '$.status') = ?", "draft") }
  scope :by_newest, -> { order(created_at: :desc) }
  scope :with_tag, ->(tag) {
    # Tags are stored as a JSON array, e.g. ["featured","sale"]. We match by
    # looking for the quoted tag substring inside the serialized array.
    where("json_extract(metadata, '$.tags') LIKE ?", "%\"#{tag}\"%")
  }

  # Return all unique tags across all products
  def self.all_tags
    products = all.to_a
    return [] if products.empty?

    tags = products.flat_map { |p| p.tags }
    tags.uniq.sort
  end

  # Delegated metadata accessors
  def title
    metadata["title"]
  end

  def group
    metadata["group"]
  end

  def variant
    metadata["variant"]
  end

  def primary?
    metadata["primary"] == true || metadata["primary"] == "true"
  end

  def url_name
    # If url_name is explicitly set, use it exactly
    explicit = metadata["url_name"]
    return explicit if explicit.present?

    # Auto-generate from title
    base = title&.parameterize
    return nil if base.blank?

    # Only append variant if: there's a group AND variant AND no explicit url_name
    if group.present? && variant.present?
      "#{base}-#{variant.parameterize}"
    else
      base
    end
  end

  def status
    metadata["status"] || "draft"
  end

  def price
    metadata["price"]&.to_f || 0.0
  end

  def sku
    metadata["sku"]
  end

  def image
    metadata["image"]
  end

  def description
    metadata["description"]
  end

  def tags
    metadata["tags"] || []
  end

  # URL helpers
  def public_url
    "/store/#{url_name}"
  end

  # Snipcart data attributes
  def snipcart_attributes
    {
      "data-item-id" => sku,
      "data-item-name" => title,
      "data-item-price" => price,
      "data-item-url" => public_url,
      "data-item-description" => description,
      "data-item-image" => image
    }.compact
  end

  def self.create_or_update_from_file(file_path)
    # Resolve symlinks (notably /rails/site → /data/site on prod) for
    # both the file and SITE_PATH so the strip below produces the
    # canonical relative key. Without this, file_path and SITE_PATH
    # use different forms and the sub doesn't match — leaving an
    # absolute path stored where a relative key was expected, which
    # then misses on subsequent lookups and creates duplicates.
    absolute_path  = RoeSitePaths.normalize(file_path)
    real_site_path = RoeSitePaths.normalize(RoeSitePaths::SITE_PATH.to_s)

    begin
      parsed = FrontMatterParser::Parser.parse_file(file_path)
    rescue => e
      Rails.logger.error "Failed to parse #{file_path}: #{e.message}"
      puts "\n  ✗ YAML parsing error: #{File.basename(file_path)}"
      puts "     #{e.message}\n"
      return nil
    end

    # File-first: save whatever's in the file, even if title or price is
    # missing. The admin warning system (Product#needs_attention?) flags
    # the gaps in the UI; ContentSync should never silently skip a file.
    if parsed.front_matter["title"].blank?
      Rails.logger.warn "Product missing title: #{file_path}"
      puts "  ⚠ Missing title: #{File.basename(file_path)}"
    end

    if parsed.front_matter["price"].blank?
      Rails.logger.warn "Product missing price: #{file_path}"
      puts "  ⚠ Missing price: #{File.basename(file_path)}"
    end

    relative_path = absolute_path.sub(real_site_path + "/", "")

    product = Product.find_or_initialize_by(file_path: relative_path)
    product.content = parsed.content
    product.metadata = parsed.front_matter

    if product.save
      product
    else
      Rails.logger.error "Failed to save product: #{product.errors.full_messages.join(', ')}"
      puts "\n  ✗ Failed to save: #{File.basename(file_path)}"
      puts "     #{product.errors.full_messages.join(', ')}\n"
      nil
    end
  rescue => e
    Rails.logger.error "Error processing product file #{file_path}: #{e.message}"
    puts "\n  ✗ Error: #{File.basename(file_path)} - #{e.message}\n"
    nil
  end

  def self.next_number_for_category(category)
    return 1 if category.blank?

    # Find all SKUs that start with this category
    pattern = "#{category.upcase}-%"
    products = where("json_extract(metadata, '$.sku') LIKE ?", pattern)

    # Extract numbers from SKUs like "BOOK-001", "BOOK-002"
    numbers = products.map do |product|
      sku = product.sku
      # Match pattern: CATEGORY-NUMBER-...
      if sku =~ /^#{Regexp.escape(category.upcase)}-(\d+)/
        $1.to_i
      end
    end.compact

    # Return next number (or 1 if none exist)
    numbers.any? ? numbers.max + 1 : 1
  end

  def self.sku_exists?(sku)
    return false if sku.blank?
    where("json_extract(metadata, '$.sku') = ?", sku).exists?
  end

  def generate_sku_suggestion(category: nil, number: nil)
    # Use category from metadata if not provided
    category ||= metadata["category"]
    category = category.presence || "PROD"

    # Get next number if not provided
    number ||= self.class.next_number_for_category(category)

    # Name from the title (single segment); details from the variant when set,
    # keeping any parameterized hyphens so e.g. "Red / L" → "RED-L".
    name    = title.to_s.parameterize.gsub("-", "").upcase.first(30)
    details = variant.to_s.parameterize.upcase.first(20)

    # Format: CATEGORY-NUMBER-NAME[-DETAILS]
    [ category.upcase, number.to_s.rjust(3, "0"), name, details ]
      .reject(&:blank?).join("-")
  end

  def self.duplicate_skus
    # Find all published products with SKUs (SQLite syntax)
    published_with_skus = where(<<~SQL.squish, "published")
      json_extract(metadata, '$.status') = ?
        AND json_extract(metadata, '$.sku') IS NOT NULL
        AND json_extract(metadata, '$.sku') != ''
    SQL

    # Group by SKU and find duplicates
    sku_counts = published_with_skus.group(Arel.sql("json_extract(metadata, '$.sku')")).count
    duplicate_skus = sku_counts.select { |sku, count| count > 1 }.keys

    # Return products with duplicate SKUs
    published_with_skus.select { |p| duplicate_skus.include?(p.sku) }
                       .group_by(&:sku)
  end

  # Returns the names of REQUIRED_FIELDS that are blank on this product.
  def missing_required_fields
    REQUIRED_FIELDS.reject { |name| metadata[name].to_s.strip.present? }
  end

  # Returns [{ field:, path:, exists: }] for every media field this
  # product sets. Mirrors Post#media_refs.
  def media_refs
    MEDIA_FIELDS.filter_map do |field|
      path = metadata[field].to_s.strip
      next if path.empty?

      exists = if path.start_with?("/media/")
                 Post.media_file_set.include?(path)
      else
                 true
      end
      { field: field, path: path, exists: exists }
    end
  end

  def missing_media_refs
    media_refs.reject { |ref| ref[:exists] }
  end

  # A published product "needs attention" if any required field is blank
  # or any media path doesn't resolve to a real file on disk. Used by
  # the admin UI to surface mistakes without blocking save.
  def needs_attention?
    return false unless status == "published"
    publish_warnings?
  end

  # Guardless version of needs_attention? — used to gate bulk publish on drafts.
  def publish_warnings?
    missing_required_fields.any? || missing_media_refs.any?
  end

  # The ProductGroup this product belongs to (2+ products sharing a `group:`
  # value), or nil when it's ungrouped or the lone holder of its group value.
  # Memoized so the edit page doesn't rescan products more than once.
  def product_group
    return @product_group if defined?(@product_group)
    @product_group = ProductGroup.for(self)
  end

  # Structural group-setup warnings (no/duplicate primary). Unlike
  # needs_attention?, these are NOT gated on publish status — they're setup
  # guidance meant to help configure the shop correctly, draft or live.
  def group_issues
    product_group&.warnings || []
  end

  # Per-product group warnings (e.g. this product is missing a variant while its
  # siblings have one). Shown on this product's own index row and edit page —
  # as opposed to #group_issues, which are group-wide (shown on the group header).
  def group_row_issues
    product_group&.row_warnings(self) || []
  end

  # Single UI trigger for the amber ⚠ (index) and the issues box (edit page):
  # the published-content check plus the always-on group checks. `primary` is an
  # ordinary optional field: unset/blank reads as false, and only one product
  # in a group needs it true, so there's no "all three must be set" rule.
  def flagged?
    needs_attention? || group_issues.any? || group_row_issues.any?
  end

  private

  def register_category
    return if metadata["category"].blank?

    category = metadata["category"].strip.downcase
    ProductCategory.add(category)
  end

  # Populate the global group list in store.yml as products adopt groups —
  # mirrors #register_category. The list feeds the editor's group autocomplete.
  def register_group
    return if group.blank?

    ProductGroup.register(group)
  end
end
