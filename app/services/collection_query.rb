# Resolves a collection/feed config to its base set of records — the shared
# selection behind both `template:` collections (HasMarkdownExtensions) and,
# soon, named feeds (feeds.yml). It answers exactly one question:
#
#   "given source + post_type/podcast/tags/category + collection membership,
#    which records?"
#
# and deliberately stops there. Ordering, limit/offset, menu curation, the
# `related:` union, and dev-only warnings are rendering concerns that stay with
# each caller, so a feed and a collection can never disagree about *membership*
# while still presenting their results differently.
#
# `records` returns an ActiveRecord relation or an Array (an Array once the
# `collection:` membership filter runs, which needs Ruby-side selection). It
# returns nil for an unknown source, so the caller can warn in development or
# render empty in production — exactly the prior behaviour.
class CollectionQuery
  def initialize(config)
    @config = config || {}
  end

  # The resolved source string, e.g. "posts" or "documentation/roe". A menu
  # with no explicit source defaults to pages; everything else to posts.
  def self.source_for(config)
    menu = config[:template].to_s.strip == "menu"
    config[:source] || (menu ? "pages" : nil) ||
      SiteConfig.default("collections", "default_source") || "posts"
  end

  # Normalize a `collection:` name filter (comma string or array) into the
  # same downcased tokens HasMetadata#collection_names returns.
  def self.normalize_names(value)
    list = value.is_a?(Array) ? value : value.to_s.split(",")
    list.map { |c| c.to_s.strip.downcase }
        .reject(&:empty?)
        .uniq
  end

  def source
    @source ||= self.class.source_for(@config)
  end

  # The filtered base set, before ordering/limit/menus/related. nil signals an
  # unknown source.
  def records
    items = base_scope
    return nil if items.nil?

    apply_membership_filter(items)
  end

  private

  def base_scope
    tags        = @config[:tags]
    category    = @config[:category]
    podcast_key = @config[:podcast]
    post_type   = @config[:post_type]
    post_type   = nil if post_type == "all"

    case source
    when "posts"
      collection = Post.published.regular_posts
      collection = collection.by_type(post_type) if post_type
      collection = apply_podcast_filter(collection, podcast_key) if podcast_key.present?
      collection = apply_tag_filters(collection, tags) if tags
      collection
    when "pages"
      collection = Page.public_pages
      collection = apply_tag_filters(collection, tags) if tags
      collection
    when "documentation"
      collection = Documentation.public_documentation.root
      collection = apply_tag_filters(collection, tags) if tags
      collection
    when %r{^documentation/}
      dir = source.sub("documentation/", "")
      collection = Documentation.public_documentation.in_directory(dir)
      collection = apply_tag_filters(collection, tags) if tags
      collection
    when "products"
      collection = Product.published
      collection = apply_category_filter(collection, category) if category
      collection = apply_tag_filters(collection, tags) if tags
      collection
    else
      nil
    end
  end

  # `collection:` membership — like tags, but a placement concept: content
  # stays invisible until a collection gathers it by name. Menus do their own
  # membership union (list ∪ tagged) in the renderer, so this plain filter
  # applies only to the non-menu templates, matching the original.
  def apply_membership_filter(items)
    return items unless @config[:collection].present? && !menu?

    wanted = self.class.normalize_names(@config[:collection])
    items.to_a.select do |item|
      item.respond_to?(:collection_names) && (item.collection_names & wanted).any?
    end
  end

  def menu?
    @config[:template].to_s.strip == "menu"
  end

  def apply_tag_filters(collection, tag_string)
    return collection if tag_string.blank?

    # Split by comma and clean up whitespace
    tags = tag_string.split(",").map(&:strip)

    # Separate positive and negative tags
    positive_tags = tags.reject { |t| t.start_with?("-") }
    negative_tags = tags.select { |t| t.start_with?("-") }.map { |t| t[1..-1] } # Remove the '-'

    # Apply positive tags (OR logic - any of these tags)
    if positive_tags.any?
      collection = collection.tagged_with(positive_tags)
    end

    # Apply negative tags (exclude all of these, but keep untagged posts)
    negative_tags.each do |neg_tag|
      collection = collection.where(
        "json_extract(metadata, '$.tags') IS NULL OR json_extract(metadata, '$.tags') NOT LIKE ?",
        "%#{neg_tag}%"
      )
    end

    collection
  end

  def apply_category_filter(collection, category)
    collection.where("json_extract(metadata, '$.category') = ?", category.strip)
  end

  def apply_podcast_filter(collection, podcast_key)
    collection.where("json_extract(metadata, '$.podcast') = ?", podcast_key.strip)
  end
end
