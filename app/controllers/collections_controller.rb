class CollectionsController < ApplicationController
  skip_before_action :require_authentication

  def show
    @filters = params[:filters]
    @page = params[:page]&.to_i || 1
    @exclude_tags = params[:exclude]&.split(",") || []
    @source = params[:source] || "posts"
    @order = params[:order] || "date"
    @heading = params[:heading]
    @podcast_key = params[:podcast]
    # Pagination-page template is global per install (configured in
    # defaults/collections.yml). Falls back to "list" if the config
    # is missing or holds an unrecognised value.
    @pagination_template = resolve_pagination_template

    parse_filters
    fetch_items
    paginate_items
    set_page_metadata
  end

  private

  def per_page
    # Use SiteConfig.default() for defaults/collections.yml
    SiteConfig.default("collections", "items_per_page")&.to_i || 20
  end

  # Templates the pagination page can render. Each value maps to a
  # partial at app/views/collections/_items_<value>.html.erb. Grid
  # and glossary are inline-only — they need block-level config (image
  # sizing, definition-list grouping) that doesn't translate to a
  # standalone archive page. Anything not in this list falls back to
  # "list".
  SUPPORTED_PAGINATION_TEMPLATES = %w[list compact links full].freeze

  def resolve_pagination_template
    value = SiteConfig.default("collections", "pagination_template").to_s
    SUPPORTED_PAGINATION_TEMPLATES.include?(value) ? value : "list"
  end

  def paginate_items
    offset = (@page - 1) * per_page
    @total_items = @items.count
    @items = @items.offset(offset).limit(per_page)
    @total_pages = (@total_items.to_f / per_page).ceil
  end

  def parse_filters
    segments = @filters.split("/")

    @post_type = nil
    @tags = []

    # If heading param exists, path is just for URL aesthetics
    # Don't parse it as tags/filters
    if @heading.present?
      return
    end

    # Check if first segment could be a heading (not a type- prefix, not 'all')
    first_segment = segments.first

    if first_segment && !first_segment.start_with?("type-") && first_segment != "all"
      # Treat as tags
      @tags.concat(first_segment.split(","))
    end

    segments.each do |segment|
      if segment.start_with?("type-")
        @post_type = segment.sub("type-", "")
      elsif segment != "all" && segment != first_segment
        @tags.concat(segment.split(","))
      end
    end
  end

  def fetch_items
    # Fetch items based on source
    @items = case @source
    when "pages"
      Page.public_pages
    when "documentation"
      Documentation.public_documentation.root
    when /^documentation\//
      Documentation.public_documentation.in_directory(@source.sub("documentation/", ""))
    else
      Post.published.regular_posts
    end

    # Apply post_type filter (only for posts)
    if @post_type && @source == "posts"
      @items = @items.by_type(@post_type)
    end

    # Apply podcast filter (only for posts)
    if @podcast_key.present? && @source == "posts"
      @items = @items.where("json_extract(metadata, '$.podcast') = ?", @podcast_key.strip)
    end

    # Apply positive tag filters (OR logic)
    if @tags.any?
      @items = @items.tagged_with(@tags)
    end

    # Apply negative tag filters (exclude these tags)
    @exclude_tags.each do |exclude_tag|
      @items = @items.where(
        "json_extract(metadata, '$.tags') IS NULL OR json_extract(metadata, '$.tags') NOT LIKE ?",
        "%#{exclude_tag}%"
      )
    end

    # Apply paid content filter (before ordering!)
    filter_config = { show_paid: params[:show_paid], current_member: current_member }
    @items = CollectionMembersFilter.filter(@items, filter_config)

    # Apply ordering
    @items = apply_ordering(@items, @order)

    @total_count = @items.count
  end

  def apply_ordering(items, order_by)
    case order_by
    when "filename"
      # Sort by file_path which includes directory structure and filename
      # This keeps it as an ActiveRecord relation for pagination
      items.order(:file_path)
    when "title"
      items.order(Arel.sql("json_extract(metadata, '$.title') ASC"))
    when "date-asc"
      items.order(Arel.sql("json_extract(metadata, '$.date') ASC NULLS LAST"))
    else # 'date' or default
      items.order(Arel.sql("json_extract(metadata, '$.date') DESC NULLS LAST"))
    end
  end

  def set_page_metadata
    # Use custom heading if provided, otherwise generate one
    @page_heading = @heading || generate_heading
    @page_description = generate_description
  end

  def generate_heading
    base_heading = case @source
    when "documentation", /^documentation\//
      "Documentation"
    when "pages"
      "Pages"
    else
      # Priority within posts: tags → post_type → archive.
      # (`@heading` itself wins at the outer level — `set_page_metadata`
      # uses `@heading || generate_heading`.)
      if @tags.any?
        @tags.map(&:titleize).join(", ")
      elsif @post_type == "podcast"
        podcast_heading
      elsif @post_type
        pluralize_post_type(@post_type)
      else
        "Archive"
      end
    end

    # Add custom heading as context if provided
    if @heading.present? && @heading != base_heading
      "#{base_heading} <span class=\"collection-context\">(#{@heading})</span>"
    else
      base_heading
    end
  end

  # Podcast pages address a specific show, not a category. Use the
  # show's title from podcast.yml when we can identify one, otherwise
  # leave it singular ("Podcast", not "Podcasts" — a cross-show list
  # is still one form). Two ways to identify a show:
  #   1. Explicit `?podcast=<key>` filter on the URL.
  #   2. All items in the (unpaginated) result share the same
  #      `podcast:` metadata value — no filter needed, the heading
  #      reflects what's actually on screen.
  def podcast_heading
    key = @podcast_key.presence || sole_podcast_key_in_results
    if key.present?
      title = PodcastConfig.get(key)&.dig("title")
      return title if title.present?
    end
    "Podcast"
  end

  def sole_podcast_key_in_results
    return nil unless @items
    base = @items.unscope(:limit, :offset)
    keys = base.pluck(Arel.sql("json_extract(metadata, '$.podcast')"))
               .compact.map { |k| k.to_s.strip }.reject(&:empty?).uniq
    keys.size == 1 ? keys.first : nil
  end

  def pluralize_post_type(type)
    # Mass nouns stay singular ("Audio", "Music"). Countable media
    # types pluralize ("Videos", "Articles").
    uncountable = %w[music audio]

    if uncountable.include?(type.downcase)
      type.titleize
    else
      type.titleize.pluralize
    end
  end

  def generate_description
    parts = []

    # Source type
    parts << "All #{@source}" unless @source == "posts"

    # Ordering
    case @order
    when "filename"
      parts << "ordered by filename"
    when "title"
      parts << "alphabetically"
    when "date-asc"
      parts << "oldest"
    else
      parts << "latest"
    end

    parts.join(" • ")
  end
end
