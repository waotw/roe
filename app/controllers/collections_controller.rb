class CollectionsController < ApplicationController
  skip_before_action :require_authentication

  def show
    @filters = params[:filters]
    @page = params[:page]&.to_i || 1
    @exclude_tags = params[:exclude]&.split(',') || []
    @source = params[:source] || 'posts'
    @order = params[:order] || 'date'
    @heading = params[:heading]

    parse_filters
    fetch_items
    paginate_items
    set_page_metadata
  end

  private

  def per_page
    # Use SiteConfig.default() for defaults/collections.yml
    SiteConfig.default('collections', 'items_per_page')&.to_i || 20
  end

  def paginate_items
    offset = (@page - 1) * per_page
    @total_items = @items.count
    @items = @items.offset(offset).limit(per_page)
    @total_pages = (@total_items.to_f / per_page).ceil
  end

  def parse_filters
    segments = @filters.split('/')

    @post_type = nil
    @tags = []

    # If heading param exists, path is just for URL aesthetics
    # Don't parse it as tags/filters
    if @heading.present?
      return
    end

    # Check if first segment could be a heading (not a type- prefix, not 'all')
    first_segment = segments.first

    if first_segment && !first_segment.start_with?('type-') && first_segment != 'all'
      # Treat as tags
      @tags.concat(first_segment.split(','))
    end

    segments.each do |segment|
      if segment.start_with?('type-')
        @post_type = segment.sub('type-', '')
      elsif segment != 'all' && segment != first_segment
        @tags.concat(segment.split(','))
      end
    end
  end

  def fetch_items
    # Fetch items based on source
    @items = case @source
    when 'pages'
      Page.public_pages
    when 'documentation'
      Documentation.public_documentation
    else
      Post.public_posts
    end

    # Apply post_type filter (only for posts)
    if @post_type && @source == 'posts'
      @items = @items.by_type(@post_type)
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

    # Apply ordering
    @items = apply_ordering(@items, @order)

    @total_count = @items.count
  end

  def apply_ordering(items, order_by)
    case order_by
    when 'filename'
      items.to_a.sort_by do |item|
        filename = File.basename(item.file_path, '.md')
        if filename =~ /^(\d+)/
          [ $1.to_i, filename ]
        else
          [ Float::INFINITY, filename ]
        end
      end
    when 'title'
      items.order(Arel.sql("json_extract(metadata, '$.title') ASC"))
    when 'date-asc'
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
    when 'documentation'
      'Documentation'
    when 'pages'
      'Pages'
    else
      if @post_type
        pluralize_post_type(@post_type)
      elsif @tags.any?
        @tags.map(&:titleize).join(', ')  # Changed from ' + ' to ', '
      else
        'Archive'
      end
    end

    # Add custom heading as context if provided
    if @heading.present? && @heading != base_heading
      "#{base_heading} <span class=\"collection-context\">(#{@heading})</span>"
    else
      base_heading
    end
  end

  def pluralize_post_type(type)
    # Media types remain singular
    uncountable = %w[music audio video]

    if uncountable.include?(type.downcase)
      type.titleize
    else
      type.titleize.pluralize
    end
  end

  def generate_description
    parts = []

    # Source type
    parts << "All #{@source}" unless @source == 'posts'

    # Ordering
    case @order
    when 'filename'
      parts << 'ordered by filename'
    when 'title'
      parts << 'alphabetically'
    when 'date-asc'
      parts << 'oldest'
    else
      parts << 'latest'
    end

    parts.join(' • ')
  end
end
