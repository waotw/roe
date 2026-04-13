# app/services/product_category.rb
class ProductCategory
  def self.all
    categories = SiteConfig.feature('store', 'product_categories') || []

    # Handle if it's stored as a string instead of array
    if categories.is_a?(String)
      categories.split(',').map(&:strip).reject(&:blank?)
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
    store_path = Rails.root.join('site/system/features/store.yml')
    config = YAML.load_file(store_path)
    config['product_categories'] = categories
    File.write(store_path, config.to_yaml)
  end
end
