# frozen_string_literal: true

# A product group is NOT persisted — it's derived at read time from product
# front-matter (`group:` / `primary:`). Roe is file-first: the files are the
# source of truth, so grouping is computed from the current product set rather
# than stored in its own table (which would need sync hooks and could drift).
#
# A "group" requires 2+ products sharing the same `group:` value; a lone
# `group:` value is treated as a normal standalone product.
class ProductGroup
  attr_reader :name, :members

  # Turn a collection of products into the ordered list of index "rows".
  # Each row is either a bare Product (ungrouped, or the only one with its
  # group value) or a ProductGroup (2+ members). Default order: groups first,
  # alphabetical by group name, then standalone products alphabetical by title.
  # Members within a group are ordered primary-first (see #ordered_members).
  def self.rows_for(products)
    buckets = products.to_a.group_by { |p| group_key(p) }
    standalones = buckets.delete(nil) || []

    groups = []
    buckets.each do |_key, members|
      if members.size >= 2
        groups << new(members.first.group.to_s.strip, members)
      else
        standalones.concat(members)
      end
    end

    groups.sort_by { |g| g.name.to_s.downcase } +
      standalones.sort_by { |p| p.title.to_s.downcase }
  end

  # The ProductGroup a single product belongs to, or nil if it's ungrouped or
  # the only product carrying its group value. Used on the edit page, where we
  # only have one product in hand but still want its group-level warnings.
  def self.for(product)
    key = group_key(product)
    return nil unless key

    members = Product.all.select { |p| group_key(p) == key }
    return nil if members.size < 2

    new(product.group.to_s.strip, members)
  end

  def self.group_key(product)
    product.group.to_s.strip.downcase.presence
  end

  # --- Registry side (mirrors ProductCategory) --------------------------------
  # The global list of known group names, stored in store.yml and populated as
  # products adopt groups (via Product#register_group). Feeds the editor's
  # group autocomplete. Distinct from the instance side above, which derives
  # the live grouping from the current product set.
  STORE_KEY = "product_groups"

  def self.all
    StoreConfigList.all(STORE_KEY)
  end

  def self.register(name)
    StoreConfigList.add(STORE_KEY, name)
  end

  # Every group name currently in use across products — de-duplicated
  # case-insensitively and sorted. The source of truth for the registry.
  def self.registry_names
    Product.all.filter_map { |p| p.group.to_s.strip.presence }
               .uniq { |n| n.downcase }
               .sort_by(&:downcase)
  end

  # Rebuild the store.yml registry from the products, then re-sync SiteConfig so
  # the change is visible immediately. Needed because the store settings form
  # rewrites store.yml from its own fields and drops product_groups (a derived,
  # read-only key) — call this right after that save so the group list and the
  # editor autocomplete survive it.
  def self.resync_registry
    StoreConfigList.write(STORE_KEY, registry_names)
    SiteConfig.sync_from_file("features/store")
  end

  # Row rank for the index sort: a group takes its most recently edited
  # member's timestamp so the whole block floats with its freshest variant.
  def self.rank(row)
    if row.is_a?(ProductGroup)
      row.members.map { |m| m.updated_at.to_i }.max
    else
      row.updated_at.to_i
    end
  end

  def initialize(name, members)
    @name = name
    @members = members
  end

  # Primary on top, then the rest by most recently edited. When the primary is
  # ambiguous (none, or more than one — both flagged by #warnings) there's no
  # clear leader, so everyone falls back to recency order.
  def ordered_members
    lead = primaries.size == 1 ? primaries : []
    rest = (members - lead).sort_by { |p| -p.updated_at.to_i }
    lead + rest
  end

  # The single primary product, or nil when it's missing/ambiguous.
  def primary
    primaries.size == 1 ? primaries.first : nil
  end

  # Structural, setup-time warnings. Deliberately NOT gated on publish status
  # (unlike Product#needs_attention?) — a mis-configured group is worth fixing
  # while you're still drafting the shop. Returned as human-readable strings so
  # they can drop straight into the product edit page's issues list.
  def warnings
    msgs = []

    if primaries.empty?
      msgs << %(This product's group ("#{name}") has no primary product. ) +
        "Mark one as primary — it's the product used for the product page and in collections."
    elsif primaries.size > 1
      msgs << %(This product's group ("#{name}") has more than one primary product: ) +
        "#{primaries.map { |p| label_for(p) }.join(', ')}. Only one should be marked primary."
    end

    # Variant distinguishes products that share a title. Flag it at the group
    # level only when EVERY member is missing one (a whole-group problem);
    # partial cases are flagged per-row instead (see #row_warnings).
    if members.all? { |m| variant_missing?(m) }
      msgs << %(No product in group "#{name}" has a variant set. Variants distinguish products that share a title (e.g. Paperback vs Hardback).)
    end

    msgs
  end

  # Per-member warnings — shown on that member's own row (index) and its edit
  # page, as opposed to #warnings, which are group-wide. A missing variant only
  # lands here when SOME (not all) members lack one; if all lack it, that's the
  # group-level warning above.
  def row_warnings(product)
    msgs = []
    if variant_missing?(product) && members.any? { |m| !variant_missing?(m) }
      msgs << "This product is missing a variant — its group has others, so a variant is needed to tell them apart."
    end
    msgs
  end

  private

  # "Title (Variant)", or just the title when there's no variant — so warnings
  # can tell apart products that share a title.
  def label_for(product)
    base = product.title.presence || product.file_path
    variant_missing?(product) ? base : "#{base} (#{product.variant.to_s.strip})"
  end

  def variant_missing?(product)
    product.variant.to_s.strip.empty?
  end

  def primaries
    @primaries ||= members.select(&:primary?)
  end
end
