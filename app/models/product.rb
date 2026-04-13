class Product < ApplicationRecord
  include HasMetadata
  include HasMarkdownExtensions
  include HasInlineFootnotes

  # Validations
  validates :file_path, presence: true, uniqueness: true
  validate :validate_required_metadata

  after_save :register_category

  # Scopes
  scope :published, -> { where("metadata->>'status' = ?", 'published') }
  scope :draft, -> { where("metadata->>'status' = ?", 'draft') }
  scope :by_newest, -> { order(created_at: :desc) }
  scope :with_tag, ->(tag) {
    where("EXISTS (SELECT 1 FROM json_array_elements_text(metadata->'tags') AS tag WHERE tag = ?)", tag)
  }

  # Delegated metadata accessors
  def title
    metadata['title']
  end

  def url_name
    metadata['url_name'] || title&.parameterize
  end

  def status
    metadata['status'] || 'draft'
  end

  def price
    metadata['price']&.to_f || 0.0
  end

  def sku
    metadata['sku']
  end

  def image
    metadata['image']
  end

  def description
    metadata['description']
  end

  def tags
    metadata['tags'] || []
  end

  # URL helpers
  def public_url
    "/store/#{url_name}"
  end

  # Snipcart data attributes
  def snipcart_attributes
    {
      'data-item-id' => sku,
      'data-item-name' => title,
      'data-item-price' => price,
      'data-item-url' => public_url,
      'data-item-description' => description,
      'data-item-image' => image
    }.compact
  end

  def self.create_or_update_from_file(file_path)
    absolute_path = File.expand_path(file_path)

    begin
      parsed = FrontMatterParser::Parser.parse_file(file_path)
    rescue => e
      Rails.logger.error "Failed to parse #{file_path}: #{e.message}"
      puts "\n  ✗ YAML parsing error: #{File.basename(file_path)}"
      puts "     #{e.message}\n"
      return nil
    end

    # Validate required fields
    if parsed.front_matter['title'].blank?
      Rails.logger.warn "Product missing title: #{file_path}"
      puts "\n  ✗ Missing title: #{File.basename(file_path)}\n"
      return nil
    end

    if parsed.front_matter['price'].blank?
      Rails.logger.warn "Product missing price: #{file_path}"
      puts "\n  ✗ Missing price: #{File.basename(file_path)}\n"
      return nil
    end

    relative_path = absolute_path.sub(Rails.root.to_s + "/", "")

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
    products = where("metadata->>'sku' LIKE ?", pattern)

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
    where("metadata->>'sku' = ?", sku).exists?
  end

  def generate_sku_suggestion(category: nil, number: nil)
    # Use category from metadata if not provided
    category ||= metadata['category']
    category = category.presence || 'PROD'

    # Get next number if not provided
    number ||= self.class.next_number_for_category(category)

    # Generate title slug (limit to 20 chars, uppercase)
    title_slug = title.to_s.parameterize.upcase.gsub('-', '').first(20)

    # Format: CATEGORY-NUMBER-TITLESLUG
    "#{category.upcase}-#{number.to_s.rjust(3, '0')}-#{title_slug}"
  end

  private

  def register_category
    return if metadata['category'].blank?

    category = metadata['category'].strip.downcase
    ProductCategory.add(category)
  end

  def validate_required_metadata
    errors.add(:metadata, "must include title") if metadata['title'].blank?
    errors.add(:metadata, "must include price") if metadata['price'].blank?

    # Only require SKU when publishing
    if metadata['status'] == 'published' && metadata['sku'].blank?
      errors.add(:metadata, "must include sku when publishing")
    end
  end
end
