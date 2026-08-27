# app/services/product_category.rb
#
# The product-category registry in system/features/store.yml.
#
# Storage is StoreConfigList's — it owns the surgical block replacement that
# keeps the rest of store.yml byte-identical, and reads back from the file it
# writes. This class used to carry its own copy of that logic and read the
# list from SiteConfig instead, which meant it decided what was already
# registered from the database while writing to the file. The two diverge
# after a sync, and the file lost categories as a result.
#
# What's left here is the one thing categories do differently from other
# registries: they're normalized to lowercase, because they're slugs rather
# than user-facing labels.
class ProductCategory
  STORE_KEY = "product_categories".freeze

  def self.all
    StoreConfigList.all(STORE_KEY)
  end

  def self.add(category)
    normalized = category.to_s.strip.downcase
    return if normalized.blank?

    StoreConfigList.add(STORE_KEY, normalized)
  end

  # Kept as a thin pass-through: the block-rewriting behaviour is covered by
  # ProductCategoryTest, and the case it guards (a column-0 list left behind,
  # producing an unparseable file) is worth keeping under this name.
  def self.rewritten_store_yaml_with_categories(path, categories)
    StoreConfigList.rewritten(path, STORE_KEY, categories)
  end

  def self.categories_yaml_block(categories)
    StoreConfigList.yaml_block(STORE_KEY, categories)
  end

  def self.update_store_config(categories)
    StoreConfigList.write(STORE_KEY, Array(categories).map { |c| c.to_s.strip.downcase }.reject(&:empty?).sort)
  end
end
