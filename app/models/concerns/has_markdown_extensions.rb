module HasMarkdownExtensions
  extend ActiveSupport::Concern

  def to_html(preview: false)
    processed_content = process_collections(content, preview: preview)
    processed_content = process_cards(processed_content, preview: preview)
    processed_content = process_inline_footnotes(processed_content)
    Kramdown::Document.new(
      processed_content,
      input: 'GFM',  # Add this to enable GitHub Flavored Markdown
      footnote_backlink: "↩"
    ).to_html
  end

  private

  def process_collections(markdown, preview: false)
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

  # CARDS

  def process_cards(markdown, preview: false)
    markdown.gsub(/```card\r?\n(.*?)```/m) do
      config_text = $1
      config = parse_card_config(config_text)
      render_card(config, preview: preview)
    end
  end

  def parse_card_config(text)
    config = {}
    text.split("\n").each do |line|
      next if line.strip.empty?
      key, value = line.split(':', 2).map(&:strip)
      config[key.to_sym] = value if key && value
    end
    config
  end

  def render_card(config, preview: false)
    type = config[:type] || 'pullquote'

    case type
    when 'pullquote'
      render_pullquote(config)
    when 'aside'
      render_aside(config)
    when 'post-link'
      render_post_link(config, preview: preview)
    else
      preview ? '<!-- Unknown card type -->' : ''
    end
  end

  def render_pullquote(config)
    text = config[:text] || ''

    <<~HTML
      <div class="card card-pullquote" markdown="1">

      #{text}
      {: .pullquote-text}

      </div>
    HTML
  end

  # POST LINKS

  def render_post_link(config, preview: false)
    # If a post reference is provided, look it up and merge its data
    if config[:post].present?
      referenced_post = find_post_by_slug(config[:post])

      if referenced_post
        # Start with post's actual data
        post_data = {
          image: referenced_post.image || '',
          title: referenced_post.title || 'Untitled',
          author: referenced_post.author || '',
          date: referenced_post.date,
          excerpt: referenced_post.excerpt || '',
          url: "/posts/#{referenced_post.url_name}"
        }

        # Override with any explicitly provided values
        config = post_data.merge(config.except(:post))
      else
        # Post not found - render error card
        return preview ? render_error_card("Post not found: #{config[:post]}") : ''
      end
    end

    style = config[:style] || 'small'
    image = config[:image] || ''
    title = config[:title] || 'Untitled'
    author = config[:author] || ''
    date_raw = config[:date] || ''
    excerpt = config[:excerpt] || ''
    url = config[:url] || '#'
    link_text = config[:link_text] || 'Read full story →'

    # Format date
    date = ''
    if date_raw.present?
      begin
        # Handle both Date objects and strings
        parsed_date = date_raw.is_a?(Date) ? date_raw : Date.parse(date_raw.to_s)
        date = parsed_date.strftime('%b %d, %Y')
      rescue
        date = date_raw.to_s  # Fallback to original if parsing fails
      end
    end

    # Build metadata line
    metadata_parts = [ author, date ].reject(&:blank?)
    metadata = metadata_parts.join(' • ')

    # Only show excerpt for large style, truncate if needed
    excerpt_html = ''
    if style == 'large' && excerpt.present?
      truncated = excerpt.length > 200 ? excerpt[0..197] + '...' : excerpt
      excerpt_html = "<p class=\"card-excerpt\">#{truncated}</p>"
    end

    <<~HTML
      <div class="card post-link-#{style}">
        #{image.present? ? "<img src=\"#{image}\" alt=\"#{title}\" class=\"card-image\">" : ''}
        <div class="card-content">
          <h4 class="card-title-#{style}">#{title}</h4>
          #{metadata.present? ? "<p class=\"card-metadata-#{style}\">#{metadata}</p>" : ''}
          #{excerpt_html}
          <a href="#{url}" class="card-link-#{style}">#{link_text}</a>
        </div>
      </div>
    HTML
  end

  def find_post_by_slug(slug_or_path)
    slug = slug_or_path.to_s.sub(%r{^/posts/}, '').sub(%r{^/}, '')
    Post.where("json_extract(metadata, '$.url_name') = ?", slug).first
  end

  def render_error_card(message)
    <<~HTML
      <div class="card card-error">
        <div class="card-content">
          <p><strong>⚠️ Card Error:</strong> #{message}</p>
        </div>
      </div>
    HTML
  end
end
