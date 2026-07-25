# app/services/product_category.rb
class ProductCategory
  def self.all
    categories = SiteConfig.feature("store", "product_categories") || []

    # Handle if it's stored as a string instead of array
    if categories.is_a?(String)
      categories.split(",").map(&:strip).reject(&:blank?)
    else
      categories
    end
  end

  def self.add(category)
    categories = all
    normalized = category.to_s.strip.downcase

    return if normalized.blank? || categories.include?(normalized)

    categories << normalized
    categories.sort!

    update_store_config(categories)
  end

  def self.update_store_config(categories)
    store_path = File.join(RoeSitePaths::SITE_PATH, "system/features/store.yml")

    begin
      # Surgical string update — replaces just the
      # `product_categories:` block, leaving every other key in
      # store.yml byte-identical (currency, default_domain,
      # grouped_products config, comments, quote styles, etc.).
      # Round-tripping through YAML.load + to_yaml would rewrite the
      # whole file in Psych's preferred style and clobber the user's
      # formatting choices.
      File.write(store_path, rewritten_store_yaml_with_categories(store_path, categories))
    rescue Errno::ENOENT, Errno::EACCES => e
      Rails.logger.error "Failed to update product categories: #{e.message}"
      # Don't raise - this is a non-critical operation
      false
    rescue Psych::SyntaxError => e
      Rails.logger.error "Invalid YAML in store.yml: #{e.message}"
      false
    end
  end

  # Read store.yml as text and replace just the `product_categories:`
  # block. Handles four cases:
  #
  #   1. product_categories: exists as a block style (lines of `- X`)
  #      → replace the block contents
  #   2. product_categories: exists as an inline array (`[a, b, c]`)
  #      → replace the whole line with a block style
  #   3. product_categories: exists with `[]` empty inline or `: ` empty
  #      → replace with new block (or `[]` if categories empty)
  #   4. product_categories: doesn't exist at all
  #      → append to the end of the file
  #
  # Always emits double-quoted category names so values with spaces
  # or special chars survive a YAML reparse.
  def self.rewritten_store_yaml_with_categories(store_path, categories)
    new_block = categories_yaml_block(categories)

    unless File.exist?(store_path)
      return new_block
    end

    content = File.read(store_path)

    in_categories_block = false
    found = false
    result_lines = []

    content.lines.each do |line|
      if !in_categories_block && line.match?(/\Aproduct_categories:\s*\Z/)
        # Bare `product_categories:` header — children follow
        found = true
        in_categories_block = true
        result_lines << new_block
        next
      end

      if !in_categories_block && line.match?(/\Aproduct_categories:\s*(\[.*\]|\S.*)\Z/)
        # Inline form: `product_categories: [a, b]` or
        # `product_categories: foo` — replace whole line
        found = true
        result_lines << new_block
        next
      end

      if in_categories_block
        if line.match?(/\A[ \t]*-\s/) || line.match?(/\A[ \t]*\Z/)
          # A `- item` (indented OR at column 0 — a block sequence may sit at
          # the parent key's indent, which is valid YAML) or a blank line: still
          # inside the block, skip (we've already emitted the replacement). The
          # earlier `[ \t]+` here missed column-0 items and left them behind,
          # producing a second, stale list and an unparseable file.
          next
        else
          # Non-indented line: we're out of the categories block
          in_categories_block = false
          result_lines << line
          next
        end
      end

      result_lines << line
    end

    result = result_lines.join

    return result if found

    # No existing product_categories — append to the end with a blank
    # separator so it visually groups apart from preceding keys.
    result.chomp + "\n\n" + new_block
  end

  # Build the YAML representation of the categories list. Returns an
  # inline `[]` for empty lists to match the convention Roe's other
  # array-valued fields use. For non-empty lists, emits a block-style
  # array with each category on its own indented line.
  def self.categories_yaml_block(categories)
    list = Array(categories).compact.map(&:to_s).reject(&:empty?)
    return "product_categories: []\n" if list.empty?

    lines = [ "product_categories:" ]
    list.each do |cat|
      escaped = cat.gsub("\\", "\\\\").gsub('"', '\\"')
      lines << %(  - "#{escaped}")
    end
    lines.join("\n") + "\n"
  end
end
