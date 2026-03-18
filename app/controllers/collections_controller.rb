class CollectionsController < ApplicationController
  skip_before_action :require_authentication

  PER_PAGE = 20

  def show
    @filters = params[:filters] # e.g., "type-music/jazz" or "all"
    @page = params[:page]&.to_i || 1
    @exclude_tags = params[:exclude]&.split(',') || []
    @source = params[:source] || 'posts' # NEW
    @order = params[:order] || 'date' # NEW
    @heading = params[:heading] # NEW

    parse_filters
    fetch_items
    paginate_items
    set_page_metadata
  end

  private

  def parse_filters
    # Split the filters path into segments
    segments = @filters.split('/')

    @post_type = nil
    @tags = []

    segments.each do |segment|
      if segment.start_with?('type-')
        @post_type = segment.sub('type-', '')
      elsif segment == 'all'
        next
      else
        @tags.concat(segment.split(','))
      end
    end

    Rails.logger.info "Parsed - source: #{@source}, post_type: #{@post_type}, tags: #{@tags}, exclude: #{@exclude_tags}, order: #{@order}"
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

  def paginate_items
    @total_pages = (@total_count.to_f / PER_PAGE).ceil

    # Handle array vs ActiveRecord relation
    if @items.is_a?(Array)
      start_index = (@page - 1) * PER_PAGE
      @items = @items[start_index, PER_PAGE] || []
    else
      @items = @items.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    end
  end

  def set_page_metadata
    # Use custom heading if provided, otherwise generate one
    @page_heading = @heading || generate_heading
    @page_description = generate_description
  end

  def generate_heading
    case @source
    when 'documentation'
      'Documentation'
    when 'pages'
      'Pages'
    else
      if @post_type
        @post_type.titleize.pluralize
      elsif @tags.any?
        @tags.map(&:titleize).join(' + ')
      else
        'Archive'
      end
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
