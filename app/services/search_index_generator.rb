# frozen_string_literal: true

# Builds the public search index consumed by the client-side site search.
# It's served both dynamically (/search-index.json) and baked into the
# static build, so search works whether a Roe site runs on Rails or is
# deployed as static HTML.
#
# Each entry: { title, url, type, post_type, tags, paid, text, excerpt }.
# `type` mirrors a collection `source` (posts/pages/documentation/products)
# and `post_type`/`tags` mirror collection filters, so the client can scope
# results to a collection or a ```search block by the same criteria.
#
# Visibility (matches public listings):
#   - published only — drafts and unlisted are excluded
#   - audience "everyone"/blank — indexed with full body text
#   - audience "paid" — indexed as a teaser (title + excerpt, no body) ONLY
#     when members `everyone.show_paid_content` is on; otherwise excluded
#   - anything else (e.g. only_paid) — excluded
class SearchIndexGenerator
  # Cap body text per entry so the index stays small; enough for useful
  # matching without shipping whole articles.
  TEXT_LIMIT = 2000

  def self.build
    new.build
  end

  def build
    { entries: entries }
  end

  private

  def entries
    out = []
    out.concat(collect(Post.published, type: "posts"))
    out.concat(collect(searchable_pages, type: "pages"))
    out.concat(collect(searchable_documentation, type: "documentation"))
    out.concat(collect(searchable_products, type: "products"))
    out
  end

  def collect(records, type:)
    records.filter_map { |record| entry_for(record, type) }
  end

  # Pages are a mixed bag (deliberate nav pages, one-off landing pages, member
  # utilities), so by default only index published pages that are actually
  # surfaced in the nav or footer. `search_all_pages: true` in site.yml opts
  # into every published public page. `unlisted` still hides a page either way
  # (it's excluded by the `.published` scope).
  def searchable_pages
    return Page.published if search_all_pages?

    paths = nav_footer_paths
    Page.published.select { |page| paths.include?(page.public_url) }
  end

  def search_all_pages?
    value = SiteConfig.content("search.all_pages")
    value == true || value == "true"
  end

  # Roe's bundled docs (documentation/roe) are excluded by default; the Roe
  # project's own site sets `search_roe_docs: true` to include them. This is
  # the SAME set the static build publishes (Documentation.publishable), so
  # "excluded from search" and "excluded from the static site" never disagree.
  def searchable_documentation
    Documentation.publishable
  end

  # Grouped products (2+ sharing a `group:`) are variants of one item, so index
  # only one representative per group — the primary — matching how product
  # collections list one row per group. Ungrouped products (and lone `group:`
  # holders) index as themselves. `ordered_members.first` is the primary when
  # one is set, otherwise the most recently edited member.
  def searchable_products
    ProductGroup.rows_for(Product.published).map do |row|
      row.is_a?(ProductGroup) ? row.ordered_members.first : row
    end
  end

  # Set of root-relative paths linked from navigation.md / footer.md.
  def nav_footer_paths
    paths = Set.new
    %w[navigation.md footer.md].each do |name|
      file = File.join(RoeSitePaths::SITE_LAYOUT_PATH, name)
      next unless File.file?(file)

      text = File.read(file)
      text.scan(%r{\]\((/[^)\s]*)\)}) { |m| paths << normalize_nav_path(m[0]) }   # [x](/path)
      text.scan(%r{href=["'](/[^"']*)["']}) { |m| paths << normalize_nav_path(m[0]) } # href="/path"
    end
    paths
  end

  def normalize_nav_path(path)
    clean = path.to_s.split(/[?#]/).first.to_s
    clean == "/" ? clean : clean.chomp("/")
  end

  def entry_for(record, type)
    # Products don't carry HasAudience — they're public store items, so treat
    # anything without audience predicates as publicly accessible.
    paid = record.respond_to?(:premium?) && record.premium?
    if paid
      return nil unless show_paid_teasers?
    elsif record.respond_to?(:publicly_accessible?) && !record.publicly_accessible?
      return nil # only_paid / non-public audiences never enter the index
    end

    text = paid ? excerpt_for(record) : full_text(record)

    {
      title: record.title.to_s,
      url: url_for(record, type),
      type: type,
      post_type: (record.post_type.to_s if record.respond_to?(:post_type)),
      tags: tags_for(record),
      paid: paid,
      excerpt: excerpt_for(record),
      text: text
    }.compact
  end

  def show_paid_teasers?
    value = SiteConfig.feature("members", "everyone.show_paid_content")
    value == true || value == "true"
  end

  def url_for(record, type)
    return record.public_url if record.respond_to?(:public_url)

    case type
    when "documentation"
      "/documentation/#{record.try(:url_name).presence || record.slug}"
    else
      "/#{record.slug}"
    end
  end

  def tags_for(record)
    return [] unless record.respond_to?(:tags)

    Array(record.tags).map(&:to_s)
  end

  def excerpt_for(record)
    record.respond_to?(:excerpt) ? record.excerpt.to_s : ""
  end

  # Plain-ish text for matching: title + a stripped, truncated body. We keep
  # this cheap (no full markdown render) — strip fenced blocks and the
  # heaviest markup, collapse whitespace, and cap the length.
  def full_text(record)
    body = record.content.to_s
                 .gsub(/```.*?```/m, " ")        # fenced blocks (code/cards/etc.)
                 .gsub(/!\[[^\]]*\]\([^)]*\)/, " ") # images
                 .gsub(/[#>*_`~\-|]/, " ")        # common markdown punctuation
                 .gsub(/\s+/, " ")
                 .strip
    [ record.title, body ].join(" ").strip[0, TEXT_LIMIT]
  end
end
