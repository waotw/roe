module HasMarkdownExtensions
  extend ActiveSupport::Concern

  def to_html(preview: false)
    # Step 1: Protect ALL fenced code blocks (4+ backticks)
    code_blocks = {}
    counter = 0

    processed_content = content.gsub(/````+.*?\n(.*?)````+/m) do
      token = "CODE_BLOCK_PLACEHOLDER_#{counter}"
      code_blocks[token] = $~.to_s
      counter += 1
      token
    end

    # Then protect regular 3-backtick blocks that aren't collection/card/gallery
    processed_content = processed_content.gsub(/```(\w+)\r?\n(.*?)```/m) do
      lang = $1
      code = $2

      # Skip if it's a collection, card, or gallery block
      next $~.to_s if [ 'collection', 'card', 'gallery' ].include?(lang)

      token = "CODE_BLOCK_PLACEHOLDER_#{counter}"
      code_blocks[token] = "```#{lang}\n#{code}```"
      counter += 1
      token
    end

    # NEW: Protect || split markers from Kramdown table processing
    pullquote_splits = {}
    processed_content = processed_content.gsub(/\|\|/) do
      token = "PULLQUOTE_SPLIT_#{counter}"
      pullquote_splits[token] = '||'
      counter += 1
      token
    end

    # Step 2: Process galleries, collections and cards
    processed_content = process_auto_galleries(processed_content)
    processed_content = process_galleries(processed_content, preview: preview)
    processed_content = process_collections(processed_content, preview: preview)
    processed_content = process_cards(processed_content, preview: preview)
    processed_content = process_inline_footnotes(processed_content)
    processed_content = process_strikethrough(processed_content)

    # Step 3: Restore code blocks
    code_blocks.each do |token, original|
      processed_content.gsub!(token, original)
    end

    # Step 4: Convert to HTML
    html = Kramdown::Document.new(
      processed_content,
      input: "kramdown",
      footnote_backlink: "",
      footnote_backlinks_inline: true,
      hard_wrap: false
    ).to_html

    # Step 5: Restore pullquote split markers AFTER Kramdown
    pullquote_splits.each do |token, original|
      html.gsub!(token, original)
    end

    # Step 6: Add custom footnote backlinks
    html = add_footnote_backlinks(html)

    # Step 7: Process collection grids (detect consecutive collections)
    html = CollectionGridProcessor.process(html)

    # Step 8: Merge floated pullquotes into following paragraphs
    html = merge_floated_pullquotes(html)

    html
  end

  private

  def process_strikethrough(markdown)
    # Convert ~~text~~ to <del>text</del> (which Kramdown preserves)
    markdown.gsub(/~~([^~]+)~~/, '<del>\1</del>')
  end

  def add_footnote_backlinks(html)
    doc = Nokogiri::HTML::DocumentFragment.parse(html)

    # Find all footnote list items
    footnotes = doc.css('.footnotes ol li')

    footnotes.each_with_index do |li, index|
      footnote_id = li['id'] # e.g., "fn:1"
      next unless footnote_id

      # Extract the footnote number/name
      ref_id = footnote_id.sub('fn:', 'fnref:')
      number = index + 1

      # Create backlink styled as a number
      backlink = Nokogiri::XML::Node.new('a', doc)
      backlink['href'] = "##{ref_id}"
      backlink['class'] = 'footnote-backlink-number'
      backlink['role'] = 'doc-backlink'
      backlink['aria-label'] = "Return to reference #{number}"
      backlink.content = "#{number}."

      # Insert at the very beginning of the <li>
      li.prepend_child(backlink)
      li.prepend_child(Nokogiri::XML::Text.new(' ', doc)) # Add space after number
    end

    doc.to_html
  end

  # GALLERIES

  def process_auto_galleries(markdown)
    lines = markdown.split("\n")
    result = []
    consecutive_images = []
    inside_fenced_block = false

    lines.each do |line|
      # Track if we're inside a fenced code block
      if line.strip =~ /^```/
        inside_fenced_block = !inside_fenced_block

        # Flush any accumulated images before entering a block
        if inside_fenced_block && consecutive_images.length >= 2
          result << "```gallery"
          result.concat(consecutive_images)
          result << "```"
          consecutive_images = []
        elsif consecutive_images.length == 1
          result.concat(consecutive_images)
          consecutive_images = []
        end

        result << line
        next
      end

      # Skip auto-gallery processing inside fenced blocks
      if inside_fenced_block
        result << line
        next
      end

      # Check if this line is an image (with optional caption)
      if line.strip =~ /^!\[([^\]]*)\]\(([^)]+)\)\s*(?:\(\*([^*]+)\*\))?$/
        consecutive_images << line
      else
        # Not an image - process any accumulated images
        if consecutive_images.length >= 2
          result << "```gallery"
          result.concat(consecutive_images)
          result << "```"
        elsif consecutive_images.length == 1
          result.concat(consecutive_images)
        end

        consecutive_images = []
        result << line
      end
    end

    # Handle any remaining consecutive images at end
    if consecutive_images.length >= 2
      result << "```gallery"
      result.concat(consecutive_images)
      result << "```"
    elsif consecutive_images.length == 1
      result.concat(consecutive_images)
    end

    result.join("\n")
  end

  def process_galleries(markdown, preview: false)
    result = markdown.gsub(/```gallery\r?\n(.*?)```/m) do
      gallery_content = $1
      html = render_gallery(gallery_content, preview: preview)

      html
    end
    result
  end

  def render_gallery(content, preview: false)
    # Split by blank lines to get rows
    rows = content.split(/\n\s*\n/).map(&:strip).reject(&:empty?)

    if rows.empty?
      return preview ? '<!-- Empty gallery -->' : ''
    end

    output = [ '' ]
    output << '{::nomarkdown}'
    output << '<div class="gallery">'

    rows.each do |row_content|
      images = []

      row_content.scan(/!\[([^\]]*)\]\(([^)]+)\)\s*(?:\(\*(.*?)\*\))?/) do
        alt_text = $1
        src = $2
        caption = $3&.strip

        images << {
          alt: alt_text,
          src: src,
          caption: caption
        }
      end

      next if images.empty?

      col_count = [ images.length, 3 ].min

      output << "  <div class=\"gallery-row gallery-col-#{col_count}\">"

      images.each do |img|
        if img[:caption].present?
          # Process caption as inline markdown
          caption_html = Kramdown::Document.new(img[:caption], input: 'GFM').to_html.strip
          # Remove wrapping <p> tags that Kramdown adds
          caption_html = caption_html.gsub(%r{^<p>(.*)</p>$}, '\1')

          output << "    <figure>"
          output << "      <img src=\"#{escape_html(img[:src])}\" alt=\"#{escape_html(img[:alt])}\">"
          output << "      <figcaption>#{caption_html}</figcaption>"
          output << "    </figure>"
        else
          output << "    <img src=\"#{escape_html(img[:src])}\" alt=\"#{escape_html(img[:alt])}\">"
        end
      end

      output << "  </div>"
    end

    output << '</div>'
    output << '{:/nomarkdown}'
    output << ''
    output.join("\n")
  end

  def escape_html(text)
    CGI.escapeHTML(text.to_s)
  end

  # COLLECTIONS

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

  def apply_tag_filters(collection, tag_string)
    return collection if tag_string.blank?

    # Split by comma and clean up whitespace
    tags = tag_string.split(',').map(&:strip)

    # Separate positive and negative tags
    positive_tags = tags.reject { |t| t.start_with?('-') }
    negative_tags = tags.select { |t| t.start_with?('-') }.map { |t| t[1..-1] } # Remove the '-'

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

  def render_collection(config)
    heading = config[:heading]
    source = config[:source] || SiteConfig.default('collections', 'default_source') || "posts"
    order_by = config[:order] || SiteConfig.default('collections', 'default_order') || "date"
    tags = config[:tags]

    # Get post_type from config or default, treating 'all' as nil (no filter)
    post_type = config[:post_type]
    post_type = nil if post_type == "all"

    # Get base collection
    items = case source
    when 'posts'
      collection = Post.public_posts
      collection = collection.by_type(post_type) if post_type
      collection = apply_tag_filters(collection, tags) if tags
      collection
    when "pages"
      collection = Page.public_pages
      collection = apply_tag_filters(collection, tags) if tags
      collection
    when "documentation"
      collection = Documentation.public_documentation
      collection = apply_tag_filters(collection, tags) if tags
      collection
    else
      []
    end

    # Apply ordering based on order parameter
    items = apply_collection_order(items, order_by)

    # Apply limit
    limit_value = config[:limit]
    default_limit = SiteConfig.default('collections', 'default_limit') || 10
    show_more = config[:show_more] == 'true' || config[:show_more] == true

    if limit_value.to_s.downcase == 'all'
      display_items = items.is_a?(Array) ? items : items.to_a
      total_count = display_items.count
    elsif limit_value
      limit_int = limit_value.to_i
      total_count = items.is_a?(Array) ? items.count : items.count
      display_items = items.is_a?(Array) ? items.take(limit_int) : items.limit(limit_int).to_a
    else
      total_count = items.is_a?(Array) ? items.count : items.count
      display_items = items.is_a?(Array) ? items.take(default_limit) : items.limit(default_limit).to_a
    end

    # Render based on template
    template = config[:template] || SiteConfig.default('collections', 'default_template') || 'list'
    list_markdown = render_template(display_items, template, config)

    # Build output with proper spacing
    output = []
    output << '<div class="collection" markdown="1">'
    output << ""

    if heading.present?
      output << "## #{heading}"
      output << ""
    end

    output << list_markdown

    # Add "View More" link ONLY for posts source
    if show_more && total_count > display_items.count && source == 'posts'
      show_more_text = config[:show_more_text] || "View all"
      collection_url = generate_collection_url(config)

      output << ""
      output << "[#{show_more_text}](#{collection_url})"
      output << "{: .collection-more}"
    end

    output << ""
    output << '</div>'

    output.join("\n")
  end

  def apply_collection_order(items, order_by)
    case order_by
    when 'filename'
      # Convert to array for filename sorting
      items.to_a.sort_by do |item|
        filename = File.basename(item.file_path, '.md')
        # Extract leading number if present
        if filename =~ /^(\d+)/
          [ $1.to_i, filename ]
        else
          [ Float::INFINITY, filename ]
        end
      end
    when 'title'
      # Alphabetical by title
      items.order(Arel.sql("json_extract(metadata, '$.title') ASC"))
    when 'date'
      # Newest first (default)
      items.order(Arel.sql("json_extract(metadata, '$.date') DESC NULLS LAST"))
    when 'date-asc'
      # Oldest first
      items.order(Arel.sql("json_extract(metadata, '$.date') ASC NULLS LAST"))
    else
      # Default to date descending
      items.order(Arel.sql("json_extract(metadata, '$.date') DESC NULLS LAST"))
    end
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
    elsif item.is_a?(Documentation)
      "/documentation/#{item.url_name}"
    else
      "/#{item.url_name}"
    end
  end

  def generate_collection_url(config)
    heading = config[:heading]
    tags = config[:tags]
    post_type = config[:post_type] unless config[:post_type] == 'all'
    order = config[:order]

    # Build base URL
    base_url = if heading.present?
      # Named collection - heading is the identifier
      "/collections/#{heading.parameterize}"
    elsif post_type || tags.present?
      # Filter-based collection
      segments = []
      segments << "type-#{post_type.parameterize}" if post_type

      if tags.present?
        positive_tags = tags.split(',').map(&:strip).reject { |t| t.start_with?('-') }
        segments << positive_tags.map(&:parameterize).join(',') if positive_tags.any?
      end

      "/collections/#{segments.join('/')}"
    else
      # No filters, no heading = general archive
      archive_page = Page.find_by("json_extract(metadata, '$.url_name') = ?", 'archive')
      archive_page ? '/archive' : '/posts'
    end

    # Add order as query param if non-default
    if order.present? && order != 'date'
      "#{base_url}?order=#{order}"
    else
      base_url
    end
  end

  ## CARDS

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
    when "pullquote"
      render_pullquote(config)
    when "aside"
      render_aside(config, preview: preview)
    when "post-link"
      render_post_link(config, preview: preview)
    else
      preview ? '<!-- Unknown card type -->' : ''
    end
  end

  ### PULLQUOTE

  def render_pullquote(config)
    text = config[:text] || ''
    attribution = config[:attribution] || ''
    position = config[:position] || SiteConfig.default("cards", "pullquote")&.[]('default_position') || 'center'

    # Build CSS classes
    pullquote_classes = [ "card", "card-pullquote", "pullquote-#{position}" ]

    output = []
    output << "<div class=\"#{pullquote_classes.join(' ')}\" markdown=\"1\">"
    output << ""
    output << text

    if attribution.present?
      output << ""
      output << "{::nomarkdown}"
      output << "<cite>— #{attribution}</cite>"
      output << "{:/nomarkdown}"
    end

    output << ""
    output << '</div>'

    output.join("\n")
  end

  def merge_floated_pullquotes(html)
    doc = Nokogiri::HTML::DocumentFragment.parse(html)

    # Find all floated pullquotes (left or right position)
    floated_pullquotes = doc.css('.pullquote-left, .pullquote-right')

    floated_pullquotes.each do |pullquote|
      # Get the next sibling element
      next_element = pullquote.next_element

      # Check if it's a paragraph
      if next_element && next_element.name == 'p'
        # Get the paragraph HTML
        para_html = next_element.inner_html

        # Check for manual split marker
        if para_html.include?('||')
          # Manual split - use the || marker
          parts = para_html.split('||', 2)
          first_half = parts[0].strip
          second_half = parts[1].strip
        else
          # Automatic split - use smart detection
          split_point = find_split_point(para_html)
          first_half = para_html[0...split_point].strip
          second_half = para_html[split_point..-1].strip
        end

        # Create a wrapper div to hold all three parts
        wrapper = Nokogiri::XML::Node.new('div', doc)
        wrapper['class'] = 'pullquote-merge'

        # Create first paragraph
        first_p = Nokogiri::XML::Node.new('p', doc)
        first_p.inner_html = first_half

        # Create second paragraph
        second_p = Nokogiri::XML::Node.new('p', doc)
        second_p.inner_html = second_half

        # Build the structure
        wrapper.add_child(first_p)
        wrapper.add_child(pullquote.dup) # Duplicate the pullquote
        wrapper.add_child(second_p)

        # Replace the original paragraph with the wrapper
        next_element.replace(wrapper)

        # Remove the original pullquote
        pullquote.remove
      end
    end

    doc.to_html
  end

  def find_split_point(text)
    # Remove HTML tags for better sentence detection
    plain_text = Nokogiri::HTML(text).text

    middle = plain_text.length / 2

    # Look for ". " near the middle (within 30% either way for more flexibility)
    search_start = [ (middle * 0.7).to_i, 0 ].max
    search_end = [ (middle * 1.3).to_i, plain_text.length ].min

    sentence_end = plain_text[search_start..search_end]&.index('. ')

    if sentence_end
      # Find this position in the original HTML text
      search_start + sentence_end + 2
    else
      # Fallback: try to split at a space near middle
      space_pos = plain_text[middle..-1]&.index(' ')
      space_pos ? middle + space_pos : middle
    end
  end

  ### POST LINKS

  def render_post_link(config, preview: false)
    # If a post reference is provided, look it up and merge its data
    if config[:post].present?
      referenced_post = find_post_by_slug(config[:post])

      if referenced_post
        # Start with post's actual data - only include image if it exists
        post_data = {
          title: referenced_post.title || 'Untitled',
          author: referenced_post.author || '',
          date: referenced_post.date,
          excerpt: referenced_post.excerpt || '',
          url: "/posts/#{referenced_post.url_name}"
        }

        # Only add image to post_data if the post has one
        post_data[:image] = referenced_post.image if referenced_post.image.present?

        # Override with any explicitly provided values
        config = post_data.merge(config.except(:post))
      else
        # Post not found - render error card
        return preview ? render_error_card("Post not found: #{config[:post]}") : ''
      end
    end

    style = config[:style] || 'small'
    title = config[:title] || 'Untitled'
    author = config[:author] || ''
    date_raw = config[:date] || ''
    excerpt = config[:excerpt] || ''
    url = config[:url] || '#'
    link_text = config[:link_text] || SiteConfig.default('cards', 'post-link')&.[]('default_link_text') || 'Read full story →'

    # Handle image with priority: explicit > post metadata > default
    image = if config.key?(:image)
      # Image key exists in config
      if config[:image] == 'none'
        nil  # Explicitly no image
      elsif config[:image].blank?
        # Empty image value - warn in preview
        Rails.logger.warn "Empty image value in post-link card for #{title}" if preview
        nil
      else
        config[:image]  # Explicitly provided image
      end
    else
      # No image key - use default
      SiteConfig.default('cards', 'post-link')&.[]('default_image')
    end

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

  ### ASIDES

  def render_aside(config, preview: false)
    text = config[:text] || ''
    image = config[:image] || ''
    link = config[:link] || ''
    link_text = config[:link_text] || ''
    default_link_text = SiteConfig.default('cards', 'aside')&.[]('default_link_text') || '→'

    # Build the content
    content = []
    content << "<img src=\"#{image}\" alt=\"\" class=\"aside-image\">" if image.present?

    # Wrap text and link in a container for mobile layout
    text_content = []

    if text.present?
      if link.present?
        if link_text.present?
          # Case 3: Link with custom link text - text separate from link
          text_content << "<div class=\"aside-text\">#{text}</div>"
          text_content << "<a href=\"#{link}\" class=\"aside-link\">#{link_text}</a>"
        else
          # Case 2: Link without link text - arrow inline with text
          text_content << "<div class=\"aside-text\"><a href=\"#{link}\" class=\"aside-link-inline\">#{text} #{default_link_text}</a></div>"
        end
      else
        # Case 1: No link - just text
        text_content << "<div class=\"aside-text\">#{text}</div>"
      end
    end

    # Wrap text content in a container for flex layout
    content << "<div class=\"aside-text-wrapper\">#{text_content.join("\n")}</div>" if text_content.any?

    # Determine if this is image-only
    aside_class = (image.present? && text.blank? && link_text.blank?) ? "card card-aside image-only" : "card card-aside"

    # Wrap in container
    <<~HTML
      <div class="aside-container">
        <div class="#{aside_class}">
          #{content.join("\n")}
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
