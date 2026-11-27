# The store's own places: the store page, and a page or listing for each
# product category.
#
#   - The store page is an ordinary page marked `page_type: store` (else the
#     file pages/store.md, else url_name `store`; SystemPages). It can live
#     at any address; product breadcrumbs link to it.
#   - A category's address is `/products/category/<category>`, where Roe
#     lists its products. A page with `category: fiction` in its metadata
#     becomes that category's page instead: the breadcrumbs link to it,
#     wherever it lives, and the listing's address redirects there.
#
# Categories are compared without regard to case: a product's `category:
# Fiction` and a page's `category: fiction` are the same category, as
# store.yml keeps them in lowercase (ProductCategory).
module StorePages
  module_function

  # The published store page, or nil.
  def store_page
    page = SystemPages.find("store")
    page if page&.published?
  end

  # The category's name as it's compared: trimmed, lowercase.
  def normalize(category) = category.to_s.strip.downcase

  # The category's part of an address: "science fiction" → "science-fiction".
  def slug(category) = normalize(category).parameterize

  # Every category a published product uses, lowercase, sorted.
  def categories
    Product.published
           .pluck(Arel.sql("json_extract(metadata, '$.category')"))
           .filter_map { |category| normalize(category).presence }
           .uniq.sort
  end

  # The category an address part names, or nil when no published product
  # is in it.
  def category_for_slug(slug)
    categories.find { |category| self.slug(category) == slug.to_s }
  end

  # The published page that's the category's own (`category:` in its
  # metadata), or nil. The oldest wins when two claim it; the links check
  # reports the second. The store page is never a category page.
  def category_page(category)
    category_pages(category).first
  end

  def category_pages(category)
    wanted = normalize(category)
    return [] if wanted.empty?

    store_id = SystemPages.find("store")&.id
    Page.where("json_extract(metadata, '$.category') IS NOT NULL")
        .order(:created_at, :id)
        .select { |page| page.published? && page.id != store_id && normalize(page.metadata["category"]) == wanted }
  end

  # Where a category's link goes: its page, else Roe's listing.
  def category_url(category)
    category_page(category)&.public_url || listing_url(category)
  end

  def listing_url(category) = "/products/category/#{slug(category)}"

  # Roe's listing for a category with no page of its own: an unsaved page
  # holding a heading and a product collection, drawn like any other page.
  # (A page's layout is its body alone, so the heading is in the body, as a
  # page written by hand would have it.)
  def listing_page(category)
    title = normalize(category).titleize
    Page.new(
      content: "# #{title}\n\n```collection\nsource: products\ncategory: #{normalize(category).gsub(/\s+/, " ")}\ntemplate: grid\n```\n",
      metadata: { "title" => title, "url_name" => "products-category-#{slug(category)}", "status" => "published" }
    )
  end

  # The category's name as a heading or crumb: its page's title, else the
  # category capitalised ("science fiction" → "Science Fiction").
  def category_title(category)
    category_page(category)&.title.presence || normalize(category).titleize
  end
end
