module HasCollections
  extend ActiveSupport::Concern

  def to_html
    processed_content = process_collections(content)
    processed_content = process_inline_footnotes(processed_content)
    Kramdown::Document.new(
      processed_content,
      input: 'GFM',  # Add this to enable GitHub Flavored Markdown
      footnote_backlink: "↩"
    ).to_html
  end

  private

  def process_collections(markdown)
    # Match fenced blocks with 'collection' language - handle both \n and \r\n
    markdown.gsub(/```collection\r?\n(.*?)```/m) do
      config_text = $1
      config = parse_collection_config(config_text)
      render_collection(config)
    end
  end

  def parse_collection_config(text)
    config = {}
    text.split("\n").each do |line|
      next if line.strip.empty?
      key, value = line.split(':', 2).map(&:strip)
      config[key.to_sym] = value if key && value
    end
    config
  end

  def render_collection(config)
    heading = config[:heading]
    source = config[:source] || 'posts'

    # Only filter by type if source is 'posts' AND a type is specified
    # AND the type isn't 'posts' (which would be redundant)
    post_type = nil
    if source == 'posts' && config[:type] && config[:type] != 'posts'
      post_type = config[:type]
    end

    # Get base collection
    items = case source
    when 'posts'
      collection = Post.public_posts # Changed from Post.published
      collection = collection.by_type(post_type) if post_type
      collection.order(Arel.sql("json_extract(metadata, '$.date') DESC NULLS LAST"))

    when 'pages'
      Page.order(:created_at)
    else
      []
    end

    # Apply limit with default - ensure it's an array
    limit_value = config[:limit]

    if limit_value.to_s.downcase == 'all'
      items = items.to_a
    elsif limit_value
      items = items.limit(limit_value.to_i).to_a
    else
      items = items.limit(10).to_a
    end

    # Render based on template
    template = config[:template] || 'list'
    list_markdown = render_template(items, template, config)

    # Build output with proper spacing
    output = []
    output << '<div class="collection" markdown="1">'
    output << ""

    if heading
      output << "## #{heading}"
      output << ""
    end

    output << list_markdown
    output << ""
    output << '</div>'

    output.join("\n")
  end

  def render_template(items, template, config)
    case template
    when 'compact'
      render_compact(items)
    when 'links'
      render_links(items)
    when 'list'
      render_list(items)
    else
      render_list(items)
    end
  end

  def render_list(items)
    items.map do |item|
      output = []
      output << '<div class="collection-item list" markdown="1">'
      output << ""

      # Title (linked)
      output << "### [#{item.title || 'Untitled'}](#{item_path(item)})"
      output << "{: .item-title}"
      output << ""

      # Subtitle
      if item.respond_to?(:subtitle) && item.subtitle.present?
        output << "*#{item.subtitle}*"
        output << "{: .item-subtitle}"
        output << ""
      end

      # Date
      if item.respond_to?(:date) && item.date
        output << "*#{item.date.strftime('%B %d, %Y')}*"
        output << "{: .item-date}"
        output << ""
      end

      output << '</div>'
      output << ""

      output.join("\n")
    end.join("\n")
  end

  def render_compact(items)
    items.map do |item|
      date_str = item.respond_to?(:date) && item.date ? " • #{item.date.strftime('%b %d, %Y')}" : ""
      "- [#{item.title || 'Untitled'}](#{item_path(item)})#{date_str}"
    end.join("\n")
  end

  def render_links(items)
    items.map do |item|
      output = []
      output << '<div class="collection-item links" markdown="1">'
      output << ""

      # Title (linked)
      output << "### [#{item.title || 'Untitled'}](#{item_path(item)})"
      output << "{: .item-title}"
      output << ""

      # Subtitle
      if item.respond_to?(:subtitle) && item.subtitle.present?
        output << "*#{item.subtitle}*"
        output << "{: .item-subtitle}"
        output << ""
      end

      output << '</div>'
      output << ""

      output.join("\n")
    end.join("\n")
  end

  def render_titles(items)
    items.map do |item|
      "- #{item.title || 'Untitled'}"
    end.join("\n")
  end

  def item_path(item)
    if item.is_a?(Post)
      "/posts/#{item.url_name}"
    else
      "/#{item.url_name}"
    end
  end
end
