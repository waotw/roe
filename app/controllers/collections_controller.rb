class CollectionsController < ApplicationController
  skip_before_action :require_authentication

  PER_PAGE = 20

  def show
    @filters = params[:filters] # e.g., "type-music/jazz" or "all"
    @page = params[:page]&.to_i || 1

    parse_filters
    fetch_items
    paginate_items
  end

  private

  def parse_filters
    # Split the filters path into segments
    segments = @filters.split('/')

    @post_type = nil
    @tag = nil

    segments.each do |segment|
      if segment.start_with?('type-')
        # Extract post type: "type-music" -> "music"
        @post_type = segment.sub('type-', '')
      elsif segment == 'all'
        # No filtering
        next
      else
        # It's a tag
        @tag = segment
      end
    end

    Rails.logger.info "Parsed filters - post_type: #{@post_type}, tag: #{@tag}"
  end

  def fetch_items
    @items = Post.public_posts

    # Apply post_type filter
    if @post_type
      @items = @items.by_type(@post_type)
    end

    # Apply tag filter
    if @tag
      @items = @items.tagged_with(@tag)
    end

    # Order by date descending
    @items = @items.order(Arel.sql("json_extract(metadata, '$.date') DESC NULLS LAST"))

    @total_count = @items.count
  end

  def paginate_items
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
    @items = @items.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
  end
end
