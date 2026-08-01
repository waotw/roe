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

  # Order items by a sort keyword (date, date-asc, title, filename, or one of
  # NUMBERED_SORTS) or, for anything else, an explicit comma-separated url_name
  # list. In-memory so it works on a relation or an Array (related:/membership
  # produce Arrays). Shared by the collection renderer and feeds.
  #
  # Matched case-insensitively, like sort_keyword? — otherwise `order: Date`
  # reads as a keyword there but falls through to the url_name list here, and
  # sorts by nothing.
  def self.order_items(items, order_by)
    case (keyword = order_by.to_s.strip.downcase)
    when "filename"
      items.to_a.sort_by do |item|
        filename = File.basename(item.file_path, ".md")
        # Extract leading number if present
        if filename =~ /^(\d+)/
          [ $1.to_i, filename ]
        else
          [ Float::INFINITY, filename ]
        end
      end
    when "title"
      items.to_a.sort_by { |item| item.title.to_s.downcase }
    when "date"
      # Newest first (default). nil dates sort to the end via a nil-safe sentinel.
      items.to_a.sort_by { |item| item.respond_to?(:date) && item.date ? item.date : Date.new(0) }.reverse
    when "date-asc"
      # Oldest first. nil dates sort to the end.
      items.to_a.sort_by { |item| item.respond_to?(:date) && item.date ? item.date : Date.new(9999) }
    when *NUMBERED_SORTS.keys
      # Ordered-media sorts: same behaviour, one per medium (see NUMBERED_SORTS).
      # Numeric so 10 follows 9; unnumbered items sort to the end alphabetically
      # so nothing is dropped.
      items.to_a.sort_by do |item|
        number = item.metadata[keyword].presence
        [ number ? number.to_s.to_f : Float::INFINITY, item.title.to_s.downcase ]
      end
    else
      explicit_order(items, order_by)
    end
  end

  # Order by an explicit, comma-separated list of url_names. Listed items come
  # first, in list order; the rest fall to the end alphabetically by title, so
  # nothing is dropped. A blank list falls back to date-descending.
  def self.explicit_order(items, order_list)
    wanted = order_list.to_s.split(",").map { |s| s.strip.downcase }.reject(&:empty?)

    if wanted.empty?
      return items.to_a.sort_by { |i| i.respond_to?(:date) && i.date ? i.date : Date.new(0) }.reverse
    end

    position = {}
    wanted.each_with_index { |name, i| position[name] ||= i }

    items.to_a.sort_by do |item|
      slug = item.respond_to?(:url_name) ? item.url_name.to_s.downcase : ""
      [ position.fetch(slug, Float::INFINITY), item.title.to_s.downcase ]
    end
  end

  # An `order:` value is a sort mode when it's one of these keywords; anything
  # else is read as an explicit url_name list.
  # Ordered-media sorts: order a collection by a number carried in metadata.
  # One per medium, identical in behaviour — a release has tracks, a podcast has
  # episodes, an audiobook has chapters. Each maps to the SiteFeature predicate
  # that gates it, so the collection builder only offers the ones a site uses.
  # A predicate that doesn't exist yet (audiobook) simply never offers its sort,
  # while the keyword still works if written by hand; adding the feature turns
  # it on with no change here.
  NUMBERED_SORTS = {
    "track_number"   => :music_enabled?,
    "episode_number" => :podcast_enabled?,
    "chapter_number" => :audiobook_enabled?
  }.freeze

  # The subset of NUMBERED_SORTS whose feature is live on this site.
  def self.enabled_numbered_sorts
    NUMBERED_SORTS.select do |_keyword, predicate|
      SiteFeature.respond_to?(predicate) && SiteFeature.public_send(predicate)
    end.keys
  end

  def self.sort_keyword?(value)
    keyword = value.to_s.strip.downcase
    %w[date date-asc title filename].include?(keyword) || NUMBERED_SORTS.key?(keyword)
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

    release_key = @config[:release]

    # By default a collection shows only published items. `show_unlisted: true`
    # widens it to published + unlisted — a player that gathers unlisted tracks,
    # a members-only list of unlisted pages, etc.
    show_unlisted = @config[:show_unlisted].to_s.strip.downcase == "true"

    case source
    when "posts"
      collection = show_unlisted ? Post.public_posts : Post.published.regular_posts
      collection = collection.by_type(post_type) if post_type
      collection = apply_podcast_filter(collection, podcast_key) if podcast_key.present?
      collection = apply_release_filter(collection, release_key) if release_key.present?
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

  # Membership in a music release — a track post carries `release: <key>`. Like
  # the podcast filter, but a separate axis, so a track can be in a release, a
  # podcast, or both.
  def apply_release_filter(collection, release_key)
    collection.where("json_extract(metadata, '$.release') = ?", release_key.strip)
  end
end
