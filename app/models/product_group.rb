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
  # group value) or a ProductGroup (2+ members). Rows are ordered by most
  # recently edited first; a group ranks by its most recently edited member,
  # so editing any variant lifts the whole block to the top. Members within a
  # group are ordered primary-first (see #ordered_members).
  def self.rows_for(products)
    buckets = products.to_a.group_by { |p| group_key(p) }
    standalones = buckets.delete(nil) || []

    rows = []
    buckets.each do |_key, members|
      if members.size >= 2
        rows << new(members.first.group.to_s.strip, members)
      else
        standalones.concat(members)
      end
    end
    rows.concat(standalones)

    rows.sort_by { |row| -rank(row) }
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
    if primaries.empty?
      [ %(This product's group ("#{name}") has no primary product. ) +
        "Mark one as primary — it's the product used for the product page and in collections." ]
    elsif primaries.size > 1
      names = primaries.map { |p| p.title.presence || p.file_path }.join(", ")
      [ %(This product's group ("#{name}") has more than one primary product ) +
        "(#{names}). Exactly one should be marked primary." ]
    else
      []
    end
  end

  private

  def primaries
    @primaries ||= members.select(&:primary?)
  end
end
