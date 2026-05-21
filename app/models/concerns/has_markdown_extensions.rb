module HasMarkdownExtensions
  extend ActiveSupport::Concern

  def to_html(preview: false)
    # Step 1: Convert backtick fenced code blocks to HTML
    code_blocks = {}
    counter = 0

    # Handle 4+ backticks first (allow optional whitespace after language)
    processed_content = content.gsub(/````+(\w*)\s*\r?\n(.*?)````+/m) do
      lang = $1.empty? ? 'text' : $1
      code = $2
      token = "CODE_BLOCK_PLACEHOLDER_#{counter}_END"
      code_blocks[token] = render_code_block(code, lang)
      counter += 1
      token
    end

    # Handle 3-backtick blocks (skip collection/card/gallery)
    processed_content = processed_content.gsub(/```(\w+)\s*\r?\n(.*?)```/m) do
      lang = $1
      code = $2

      # Skip special blocks
      if [ 'collection', 'card', 'gallery', 'form', 'button' ].include?(lang)
        next $~.to_s
      end

      token = "CODE_BLOCK_PLACEHOLDER_#{counter}_END"
      code_blocks[token] = if lang == 'poetry'
        render_poetry_block(code)
      else
        render_code_block(code, lang)
      end
      counter += 1
      token
    end

    # Protect || split markers from Kramdown's table parsing. Every
    # marker restores to the same value, so a single shared placeholder
    # is enough — no per-occurrence indexing needed.
    processed_content = processed_content.gsub('||', 'PULLQUOTE_SPLIT_END')

    # Process galleries, collections, cards, etc.
    processed_content = process_auto_galleries(processed_content)
    processed_content = process_galleries(processed_content, preview: preview)
    processed_content = process_collections(processed_content, preview: preview)
    processed_content = process_cards(processed_content, preview: preview)
    processed_content = process_forms(processed_content, preview: preview)
    processed_content = process_buttons(processed_content, preview: preview)
    processed_content = process_inline_footnotes(processed_content)
    processed_content = process_strikethrough(processed_content)
    processed_content = escape_inline_pipes(processed_content)

    # Convert to HTML with standard Kramdown
    html = Kramdown::Document.new(
      processed_content,
      input: "kramdown",
      footnote_backlink: "",
      footnote_backlinks_inline: true,
      hard_wrap: false
    ).to_html

    # Restore code blocks (now as HTML)
    code_blocks.each do |token, html_code|
      html.gsub!(token, html_code)
    end

    # Restore pullquote splits
    html.gsub!('PULLQUOTE_SPLIT_END', '||')

    # Add footnote backlinks
    html = add_footnote_backlinks(html)

    # Process collection grids
    html = CollectionGridProcessor.process(html)

    # Merge floated pullquotes
    html = merge_floated_pullquotes(html)

    # Process images to make them responsive
    html = process_responsive_images(html)

    html
  end

  def process_responsive_images(html)
    html.gsub(/<img([^>]*?)src=["']([^"']+)["']([^>]*?)>/i) do
      match_str = $~.to_s
      pre_attrs = $1
      src = $2
      post_attrs = $3

      # Check for data-sizes attribute
      sizes = if match_str =~ /data-sizes=["']([^"']+)["']/
                $1
      else
                '(min-width: 1200px) 1200px, 100vw'  # Default for non-gallery images
      end

      # Extract other attributes...
      alt = if pre_attrs =~ /alt=["']([^"']+)["']/i || post_attrs =~ /alt=["']([^"']+)["']/i
              $1
      else
              ''
      end

      css_class = if pre_attrs =~ /class=["']([^"']+)["']/i || post_attrs =~ /class=["']([^"']+)["']/i
                    $1
      else
                    ''
      end

      next match_str unless ImageVariantGenerator::IMAGE_EXTENSIONS.include?(File.extname(src).downcase)

      # Skip imgs whose src already points into the variants directory.
      # render_product_grid / render_full emit `<picture><img src=/media/
      # images/variants/foo-medium.jpeg></picture>` themselves; without
      # this guard the regex sweep below would re-pipe that variant src
      # back into ResponsiveImageRenderer and emit variants-of-variants
      # (`/variants/variants/foo-medium-medium.jpeg`).
      next match_str if src.include?("/media/images/variants/")

      ResponsiveImageRenderer.render(src, alt: alt, class: css_class, sizes: sizes)
    end
  end

  private

  def render_code_block(code, language)
    escaped_code = CGI.escapeHTML(code)
    lang_class = language.empty? ? '' : " class=\"language-#{CGI.escapeHTML(language)}\""
    "<pre><code#{lang_class}>#{escaped_code}</code></pre>"
  end

  # Poetry blocks preserve whitespace exactly (newlines, indentation,
  # multiple spaces) but still allow inline emphasis and links. Markdown
  # isn't processed inside `<pre>`, so we convert emphasis to HTML tags
  # ourselves before wrapping. Style with CSS .poetry as desired.
  def render_poetry_block(content)
    text = content.sub(/\n\z/, "")        # drop the newline before the closing fence
    text = render_poetry_inline(text)
    "<pre class=\"poetry\">#{text}</pre>"
  end

  def render_poetry_inline(text)
    text = CGI.escapeHTML(text)
    # Order matters: ** before * so the bold opener isn't eaten by italic.
    text = text.gsub(/\*\*(.+?)\*\*/) { "<strong>#{$1}</strong>" }
    text = text.gsub(/\*(.+?)\*/) { "<em>#{$1}</em>" }
    text = text.gsub(/~~(.+?)~~/) { "<s>#{$1}</s>" }
    text = text.gsub(/\[([^\]]+)\]\(([^)]+)\)/) do
      "<a href=\"#{CGI.escapeHTML($2)}\">#{$1}</a>"
    end
    text
  end

  def process_strikethrough(markdown)
    # Convert ~~text~~ to <del>text</del> (which Kramdown preserves)
    markdown.gsub(/~~([^~]+)~~/, '<del>\1</del>')
  end

  def table_separator_line?(line)
    # Matches separator lines like: | --- | --- | or |:---|---:|
    # With optional blockquote marker: > | --- | --- |
    line.match?(/^\s*>?\s*\|?\s*:?-+:?\s*\|[\s\|:-]+$/)
  end

  def part_of_table?(line, prev_line, next_line)
    # Is this line itself a separator?
    return true if table_separator_line?(line)

    # Is the next line a separator? (current line is a table header)
    return true if next_line && table_separator_line?(next_line)

    # Is the previous line a separator? (current line is a table data row)
    return true if prev_line && table_separator_line?(prev_line)

    false
  end

  def escape_inline_pipes(content)
    lines = content.split("\n")
    in_table = false

    lines.map.with_index do |line, i|
      next_line = i < lines.length - 1 ? lines[i + 1] : nil

      # Check if we're entering a table (next line is separator)
      if next_line && table_separator_line?(next_line)
        in_table = true
      end

      # Check if this is a separator line
      if table_separator_line?(line)
        in_table = true
        next line
      end

      # If in table and line starts with pipe, it's a table row
      if in_table && line.match?(/^\s*>?\s*\|/)
        next line
      end

      # If we were in a table but this line doesn't start with pipe, we've exited
      if in_table && !line.match?(/^\s*>?\s*\|/)
        in_table = false
      end

      # Not in table, escape pipes
      line.gsub(/\|/, '&#124;')
    end.join("\n")
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

      # Set sizes based on column count
      sizes = case col_count
      when 1 then '(min-width: 1200px) 1200px, 100vw'  # Featured/full width
      when 2 then '(min-width: 1024px) 50vw, 100vw'     # 2 columns
      else '(min-width: 1024px) 33vw, (min-width: 768px) 50vw, 100vw'  # 3 columns
      end

      output << "  <div class=\"gallery-row gallery-col-#{col_count}\">"

      images.each do |img|
        if img[:caption].present?
          caption_html = Kramdown::Document.new(img[:caption], input: 'GFM').to_html.strip
          caption_html = caption_html.gsub(%r{^<p>(.*)</p>$}, '\1')

          output << "    <figure>"
          # Pass sizes as data attribute
          output << "      <img src=\"#{escape_html(img[:src])}\" alt=\"#{escape_html(img[:alt])}\" data-sizes=\"#{sizes}\">"
          output << "      <figcaption>#{caption_html}</figcaption>"
          output << "    </figure>"
        else
          output << "    <img src=\"#{escape_html(img[:src])}\" alt=\"#{escape_html(img[:alt])}\" data-sizes=\"#{sizes}\">"
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

  def apply_category_filter(collection, category)
    collection.where("json_extract(metadata, '$.category') = ?", category.strip)
  end

  def apply_podcast_filter(collection, podcast_key)
    collection.where("json_extract(metadata, '$.podcast') = ?", podcast_key.strip)
  end

  def render_collection(config)
    heading = config[:heading]
    source = config[:source] || SiteConfig.default('collections', 'default_source') || "posts"
    order_by = config[:order] || SiteConfig.default('collections', 'default_order') || "date"
    tags = config[:tags]
    category = config[:category]
    podcast_key = config[:podcast]

    # Get post_type from config or default, treating 'all' as nil (no filter)
    post_type = config[:post_type]
    post_type = nil if post_type == "all"

    # Get base collection
    items = case source
    when 'posts'
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
      collection = Documentation.public_documentation
      collection = apply_tag_filters(collection, tags) if tags
      collection
    when "products"
      collection = Product.published
      collection = apply_category_filter(collection, category) if category
      collection = apply_tag_filters(collection, tags) if tags
      collection
    else
      []
    end

    # Apply paid content filter (before ordering!)
    items = CollectionMembersFilter.filter(items, config)

    # Apply ordering based on order parameter
    items = apply_collection_order(items, order_by)

    # Apply offset and limit
    offset_value = config[:offset].to_i
    limit_value = config[:limit]
    default_limit = SiteConfig.default('collections', 'default_limit') || 10
    show_more = config[:show_more] == 'true' || config[:show_more] == true

    # Convert to array if needed
    items_array = items.is_a?(Array) ? items : items.to_a
    total_count = items_array.count

    # Apply offset (skip first N items)
    items_array = items_array[offset_value..-1] || [] if offset_value > 0

    if limit_value.to_s.downcase == 'all'
      display_items = items_array
    elsif limit_value
      limit_int = limit_value.to_i
      display_items = items_array.take(limit_int)
    else
      display_items = items_array.take(default_limit)
    end

    # Render based on template, default to 'grid' for products, otherwise use configured default
    default_template = source == 'products' ? 'grid' : (SiteConfig.default('collections', 'default_template') || 'list')
    template = config[:template] || default_template
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
    when 'grid'
      render_product_grid(items, config)
    when 'compact'
      render_compact(items)
    when 'links'
      render_links(items)
    when 'full'
      render_full(items, config)
    when 'list'
      render_list(items, config)
    else
      render_list(items, config)
    end
  end

  def render_list(items, config = {})
    show_author = collection_truthy?(config[:show_author])

    items.map do |item|
      output = []
      output << '<div class="collection-item list" markdown="1">'
      output << ""

      # Title (linked) with optional lock icon
      title_html = item.title || 'Untitled'
      title_html += "<span>&nbsp;</span>#{paid_lock_icon}" if show_paid_indicator?(item)
      output << "### [#{title_html}](#{item_path(item)})"
      output << "{: .item-title}"
      output << ""

      # Subtitle
      if item.respond_to?(:subtitle) && item.subtitle.present?
        output << "*#{item.subtitle}*"
        output << "{: .item-subtitle}"
        output << ""
      end

      # Meta row: date, optionally with " • author" appended
      meta = collection_item_meta(item, show_author: show_author)
      if meta.present?
        output << "*#{meta}*"
        output << "{: .item-date}"
        output << ""
      end

      output << '</div>'
      output << ""

      output.join("\n")
    end.join("\n")
  end

  # Image-on-the-right template. Includes everything from `list`, plus
  # excerpt and a featured image. show_author defaults to TRUE for this
  # template (opposite of list); pass `show_author: false` to suppress.
  # show_excerpt also defaults to true.
  #
  # Media column rendering:
  # - Image present: `<img>` rendered; the CSS flex layout puts it on the right.
  # - post_type video/podcast/audio: a play (video) or headphones (audio-only)
  #   icon overlays the image. Without an image, the icon stands alone in the
  #   media column with no background.
  # - No image and not a media post: media column omitted, body flows full width.
  def render_full(items, config = {})
    show_author = collection_truthy?(config[:show_author], default: true)
    show_excerpt = collection_truthy?(config[:show_excerpt], default: true)

    items.map do |item|
      image_url = item.respond_to?(:image) ? item.image : nil
      has_image = image_url.present?
      icon_type = collection_media_icon(item)
      has_media_column = has_image || !icon_type.nil?
      alt = (item.title || '').to_s.gsub('"', '&quot;')

      output = []
      output << '<div class="collection-item full">'
      output << '  <div class="collection-item__body" markdown="1">'
      output << ""

      title_html = item.title || 'Untitled'
      title_html += "<span>&nbsp;</span>#{paid_lock_icon}" if show_paid_indicator?(item)
      output << "### [#{title_html}](#{item_path(item)})"
      output << "{: .item-title}"
      output << ""

      if item.respond_to?(:subtitle) && item.subtitle.present?
        output << "*#{item.subtitle}*"
        output << "{: .item-subtitle}"
        output << ""
      end

      if show_excerpt && item.respond_to?(:excerpt) && item.excerpt.present?
        output << item.excerpt.to_s
        output << "{: .item-excerpt}"
        output << ""
      end

      meta = collection_item_meta(item, show_author: show_author)
      if meta.present?
        output << "*#{meta}*"
        output << "{: .item-date}"
        output << ""
      end

      output << "  </div>"

      if has_media_column
        col_classes = [ 'collection-item__image' ]
        col_classes << 'collection-item__image--icon-only' unless has_image
        output << %Q(  <a class="#{col_classes.join(' ')}" href="#{item_path(item)}">)
        output << "    #{ResponsiveImageRenderer.render(image_url, alt: alt)}" if has_image
        if icon_type
          output << %Q(    <span class="collection-item__media-icon">#{render_media_icon(icon_type)}</span>)
        end
        output << '  </a>'
      end

      output << '</div>'
      output << ""

      output.join("\n")
    end.join("\n")
  end

  # Returns :play / :headphones / nil based on post type and media fields.
  # Only audio/video/podcast posts get an icon. For podcast posts (which can
  # carry both audio and video), video wins.
  def collection_media_icon(item)
    return nil unless item.respond_to?(:post_type)
    return nil unless %w[video podcast audio].include?(item.post_type.to_s)

    has_video = item.respond_to?(:video) && item.video.present?
    return :play if has_video

    has_audio = item.respond_to?(:audio) && item.audio.present?
    return :headphones if has_audio

    nil
  end

  # Inline SVG for the media icons used in collection-item full template.
  # Inline so we don't pay a request per item; uses currentColor so CSS
  # controls the color (white when overlaid on an image, muted otherwise).
  def render_media_icon(type)
    case type
    when :play
      %Q(<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 16.1328 15.7715"><rect height="15.7715" opacity="0" width="16.1328" x="0" y="0"/>
        <path d="M15.7715 7.88086C15.7715 12.2266 12.2363 15.7617 7.88086 15.7617C3.53516 15.7617 0 12.2266 0 7.88086C0 3.53516 3.53516 0 7.88086 0C12.2363 0 15.7715 3.53516 15.7715 7.88086ZM5.5957 5.14648L5.5957 10.625C5.5957 11.0254 6.04492 11.2207 6.43555 10.9766L10.9473 8.33008C11.2988 8.13477 11.2891 7.64648 10.9473 7.44141L6.43555 4.79492C6.08398 4.58008 5.5957 4.74609 5.5957 5.14648Z" fill="currentColor" fill-opacity="0.85"/></svg>)
    when :headphones
      %Q(<svg viewBox="0 0 16.1328 15.7715" fill="currentColor" aria-hidden="true"><path d="M15.7715 7.89062C15.7715 12.2363 12.2363 15.7715 7.88086 15.7715C3.53516 15.7715 0 12.2363 0 7.89062C0 3.54492 3.53516 0.00976562 7.88086 0.00976562C12.2363 0.00976562 15.7715 3.54492 15.7715 7.89062ZM3.56445 7.89062C3.56445 9.43359 3.92578 10.5273 4.54102 11.582C4.69727 11.8652 5.01953 11.9727 5.32227 11.8359C5.54688 12.0801 5.89844 12.1875 6.26953 12.0605C6.82617 11.9141 7.08984 11.4355 6.93359 10.8887L6.38672 8.93555C6.23047 8.37891 5.75195 8.10547 5.19531 8.26172C5.03906 8.31055 4.90234 8.37891 4.80469 8.4668C4.78516 8.28125 4.77539 8.0957 4.77539 7.89062C4.77539 5.82031 6.02539 4.46289 7.89062 4.46289C9.77539 4.46289 11.0254 5.83008 11.0254 7.89062C11.0254 8.0957 11.0156 8.29102 11.0059 8.48633C10.8887 8.38867 10.7617 8.31055 10.5859 8.26172C10.0488 8.10547 9.57031 8.37891 9.41406 8.93555L8.85742 10.8984C8.70117 11.4453 8.95508 11.9141 9.51172 12.0605C9.89258 12.1777 10.2344 12.0801 10.4688 11.8359C10.7715 11.9727 11.084 11.8652 11.2598 11.582C11.8848 10.4883 12.2363 9.4043 12.2363 7.89062C12.2363 5.12695 10.4883 3.25195 7.89062 3.25195C5.30273 3.25195 3.56445 5.11719 3.56445 7.89062Z"/></svg>)
    end
  end

  # Build the "date • author" meta line for collection items. Author is
  # only included when show_author is truthy AND the post (or site
  # config) actually has an author to show.
  def collection_item_meta(item, show_author: false)
    parts = []

    if item.respond_to?(:date) && item.date
      parts << item.date.strftime('%B %d, %Y')
    end

    if show_author
      author = item.metadata['author'].to_s.strip
      author = SiteConfig.get('author').to_s.strip if author.blank?
      parts << author if author.present?
    end

    parts.join(' • ')
  end

  # Collection-block options arrive as strings ("true"/"false") or as
  # parsed booleans depending on caller. Returns the boolean intent;
  # use `default:` to set what `nil` means.
  def collection_truthy?(val, default: false)
    return default if val.nil?
    val == true || val.to_s.downcase == 'true'
  end

  def render_compact(items)
    items.map do |item|
      date_str = item.respond_to?(:date) && item.date ? " • #{item.date.strftime('%b %d, %Y')}" : ""
      lock_icon = show_paid_indicator?(item) ? "<span>&nbsp;</span>#{paid_lock_icon}" : ""
      "- [#{item.title || 'Untitled'}#{lock_icon}](#{item_path(item)})#{date_str}"
    end.join("\n")
  end

  def render_links(items)
    items.map do |item|
      output = []
      output << '<div class="collection-item links" markdown="1">'
      output << ""

      # Title (linked) with optional lock icon
      title_html = item.title || 'Untitled'
      title_html += "<span>&nbsp;</span>#{paid_lock_icon}" if show_paid_indicator?(item)
      output << "### [#{title_html}](#{item_path(item)})"
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

  def render_product_grid(items, config)
    # Get currency symbol from store config
    currency_symbol = get_currency_symbol

    # Check if description should be shown
    show_description = config[:show_description] == 'true' || config[:show_description] == true

    # Check if grouping is enabled
    groups_enabled = config[:groups] == 'enabled' || config[:groups] == true

    # Get aspect ratio setting (default to 'auto')
    aspect_ratio = config[:aspect_ratio] || 'auto'
    image_class = "img-#{aspect_ratio}"

    # Get grouped product settings
    grouped_config = SiteConfig.feature('store', 'grouped_products') || {}
    grouped_button_text = grouped_config['button_text'].presence
    price_display_mode = grouped_config['price_display'] || 'range'
    price_separator = grouped_config['price_separator'].presence || '-'

    # Group items by their group field if groups enabled, otherwise show all
    if groups_enabled
      # Group items by their group field
      grouped_items = items.group_by do |item|
        item.respond_to?(:group) && item.group.present? ? item.group : item.id
      end
    else
      # No grouping - each item is its own group
      grouped_items = items.map { |item| [item.id, [item]] }.to_h
    end

    output = []
    output << '<div class="product-grid">'

    grouped_items.each do |group_id, group_products|
      # Determine which product to display
      display_product = determine_display_product(group_products)
      next unless display_product

      # Check if this is a grouped product
      is_grouped = group_products.length > 1

      output << '  <div class="grid-item">'

      # Product image
      image_url = display_product.respond_to?(:image) ? display_product.image : nil
      image_url = '/media/images/404.png' if image_url.blank?

      output << %Q(    <div class="grid-item-image">)
      output << %Q(      <a href="#{item_path(display_product)}">)
      output << "        #{ResponsiveImageRenderer.render(image_url, alt: (display_product.title || 'Product'), class: image_class)}"
      output << %Q(      </a>)
      output << %Q(    </div>)

      # Product title (linked)
      output << %Q(    <div class="grid-item-title">)
      output << %Q(      <a href="#{item_path(display_product)}">#{display_product.title || 'Untitled'}</a>)
      output << %Q(    </div>)

      # Show variants if grouped
      if is_grouped
        variants = group_products.map { |p| p.variant || 'Standard' }.compact.join(', ')
        output << %Q(    <div class="grid-item-variants">(#{variants})</div>)
      end

      # Optional description
      if show_description && display_product.respond_to?(:description) && display_product.description.present?
        # Truncate to ~100 characters
        desc = display_product.description.length > 100 ? display_product.description[0..97] + '...' : display_product.description
        output << %Q(    <div class="grid-item-description">#{desc}</div>)
      end

      # Price and button
      output << '    <div class="grid-item-footer">'

      if is_grouped
        # Show price based on config setting
        prices = group_products.map { |p| p.price.to_f }.compact
        if prices.any?
          formatted_price = case price_display_mode
          when 'lowest'
            "#{currency_symbol}#{sprintf('%.2f', prices.min)}"
          when 'highest'
            "#{currency_symbol}#{sprintf('%.2f', prices.max)}"
          else # 'range' or default
            if prices.min == prices.max
              "#{currency_symbol}#{sprintf('%.2f', prices.min)}"
            else
              "#{currency_symbol}#{sprintf('%.2f', prices.min)} #{price_separator} #{currency_symbol}#{sprintf('%.2f', prices.max)}"
            end
          end
          output << %Q(      <span class="grid-item-price">#{formatted_price}</span>)
        end

        # View button for grouped products - only render if button text is set
        if grouped_button_text.present?
          primary_for_link = find_primary_product(group_products) || display_product
          output << %Q(      <a href="#{item_path(primary_for_link)}" class="grid-item-button">#{grouped_button_text}</a>)
        end
      else
        # Single product - show individual price and Add to Cart
        if display_product.respond_to?(:price)
          price_formatted = "#{currency_symbol}#{sprintf('%.2f', display_product.price)}"
          output << %Q(      <span class="grid-item-price">#{price_formatted}</span>)
        end

        # Add to Cart button (if product has SKU)
        if display_product.respond_to?(:sku) && display_product.sku.present?
          product_url = item_path(display_product)
          domain = SiteConfig.feature('store', 'default_domain')
          validation_url = domain ? "https://#{domain}#{product_url}" : product_url

          output << %Q(      <button class="snipcart-add-item grid-item-button")
          output << %Q(              data-turbo="false")
          output << %Q(              data-item-id="#{display_product.sku}")
          output << %Q(              data-item-name="#{display_product.title}")
          output << %Q(              data-item-price="#{display_product.price}")
          output << %Q(              data-item-url="#{validation_url}")
          if display_product.respond_to?(:description) && display_product.description.present?
            output << %Q(              data-item-description="#{display_product.description.gsub('"', '&quot;')}")
          end
          if display_product.respond_to?(:image) && display_product.image.present?
            output << %Q(              data-item-image="#{display_product.image}")
          end
          output << %Q(      >Add to Cart</button>)
        end
      end

      output << '    </div>' # Close grid-item-footer
      output << '  </div>' # Close grid-item
    end

    output << '</div>' # Close product-grid
    output.join("\n")
  end

  # Determine which product to display from a group
  # Priority: primary → has SKU → oldest (created first)
  def determine_display_product(products)
    return products.first if products.length == 1

    # First, check for primary product
    primary = find_primary_product(products)
    return primary if primary

    # Next, prefer product with SKU
    with_sku = products.find { |p| p.respond_to?(:sku) && p.sku.present? }
    return with_sku if with_sku

    # Finally, return oldest (first created)
    products.sort_by(&:created_at).first
  end

  # Find the primary product in a group (if one exists)
  def find_primary_product(products)
    products.find { |p| p.respond_to?(:primary?) && p.primary? }
  end

  def get_currency_symbol
    currency = SiteConfig.feature('store', 'currency') || 'usd'
    case currency.downcase
    when 'usd' then '$'
    when 'eur' then '€'
    when 'gbp' then '£'
    when 'cad' then 'CA$'
    when 'aud' then 'A$'
    when 'jpy' then '¥'
    else currency.upcase
    end
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
    elsif item.is_a?(Product)
      "/store/#{item.url_name}"
    else
      "/#{item.url_name}"
    end
  end

  def generate_collection_url(config)
    heading = config[:heading]
    tags = config[:tags]
    post_type = config[:post_type] unless config[:post_type] == 'all'
    order = config[:order]
    source = config[:source] || 'posts'  # ← ADD THIS
    podcast_key = config[:podcast]

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

    # Build query params (NEW)
    query_params = []

    # Always pass source if non-default
    query_params << "source=#{source}" if source != 'posts'

    # Pass heading if it's a heading-based collection (so controller knows it's not a tag)
    query_params << "heading=#{CGI.escape(heading)}" if heading.present?

    # Add order if non-default
    query_params << "order=#{order}" if order.present? && order != 'date'

    # Add podcast key if present
    query_params << "podcast=#{CGI.escape(podcast_key)}" if podcast_key.present?

    # Add exclude tags if present
    if tags.present?
      exclude_tags = tags.split(',').map(&:strip).select { |t| t.start_with?('-') }.map { |t| t.sub('-', '') }
      query_params << "exclude=#{exclude_tags.join(',')}" if exclude_tags.any?
    end

    # Combine base URL with query params
    if query_params.any?
      "#{base_url}?#{query_params.join('&')}"
    else
      base_url
    end
  end

  def show_paid_indicator?(item)
    return false unless item.metadata['audience'] == 'paid'
    return false unless SiteConfig.feature_enabled?('members')

    # Always show indicator for paid content
    true
  end

  def paid_lock_icon
    '<svg class="paid-lock-icon" viewBox="0 0 16 16" fill="currentColor" width="18" height="18"><path d="M7.88 15.76c4.36 0 7.89-3.53 7.89-7.88 0-4.36-3.53-7.88-7.89-7.88C3.54 0 0 3.52 0 7.88c0 4.35 3.54 7.88 7.88 7.88zm0-1.48c-3.54 0-6.39-2.86-6.39-6.4 0-3.54 2.85-6.4 6.39-6.4 3.54 0 6.4 2.86 6.4 6.4 0 3.54-2.86 6.4-6.4 6.4z"/><path d="M5.12 10.89c0 .56.24.82.77.82h3.97c.52 0 .77-.26.77-.82V7.87c0-.51-.22-.77-.64-.81v-.86c0-1.45-.85-2.42-2.12-2.42-1.26 0-2.12.97-2.12 2.42v.86c-.42.04-.64.3-.64.82zm1.52-3.84V6.1c0-.88.49-1.46 1.23-1.46s1.24.58 1.24 1.46v.95z"/></svg>'
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
          author: referenced_post.author || '',  # Will be further processed below
          date: referenced_post.date,
          subtitle: referenced_post.metadata['subtitle'] || '',
          excerpt: referenced_post.metadata['excerpt'] || '',
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
    date_raw = config[:date] || ''
    subtitle = config[:subtitle] || ''
    excerpt = config[:excerpt] || ''
    url = config[:url] || '#'
    link_text = config[:link_text] || SiteConfig.default('cards', 'post-link')&.[]('default_link_text') || 'Read full story →'

    # Author fallback chain: card config -> post metadata -> site config -> blank
    author = if config[:author].present?
      config[:author]  # 1. Explicitly provided in card
    elsif config[:post].present?
      referenced_post = find_post_by_slug(config[:post])
      referenced_post&.author.presence  # 2. From post metadata
    else
      nil
    end
    author ||= SiteConfig.get('author')  # 3. From site config (FIXED)
    author ||= ''  # 4. Blank if none found

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

    # Build metadata line (author • date)
    metadata_parts = [ author, date ].reject(&:blank?)
    metadata = metadata_parts.join(' • ')

    # For large style: show subtitle if available, fallback to excerpt, otherwise nothing
    body_html = ''
    if style == 'large' || style == 'medium'
      body_text = subtitle.present? ? subtitle : excerpt
      if body_text.present?
        # Medium gets shorter excerpt than large
        max_length = style == 'large' ? 200 : 120
        truncated = body_text.length > max_length ? body_text[0..max_length-3] + '...' : body_text
        body_html = "<p class=\"card-body\">#{truncated}</p>"
      end
    end

    # Build HTML based on style
    if style == 'large'
      # Large style: title, metadata, image, body, link
      <<~HTML
        <div class="card post-link-#{style}">
          <div class="card-content">
            <h4 class="card-title-#{style}">#{title}</h4>
            #{metadata.present? ? "<p class=\"card-metadata-#{style}\">#{metadata}</p>" : ''}
          </div>
          #{image.present? ? "<img src=\"#{image}\" alt=\"#{title}\" class=\"card-image\" data-sizes=\"(min-width: 768px) 600px, 100vw\">" : ''}
          <div class="card-content">
            #{body_html}
            <a href="#{url}" class="card-link-#{style}">#{link_text}</a>
          </div>
        </div>
      HTML
    elsif style == 'medium'
      # Medium style: image, title, metadata, excerpt, link (smaller than large)
      <<~HTML
        <div class="card post-link-#{style}">
          #{image.present? ? "<img src=\"#{image}\" alt=\"#{title}\" class=\"card-image\" data-sizes=\"(min-width: 768px) 400px, 100vw\">" : ''}
          <div class="card-content">
            <h4 class="card-title-#{style}">#{title}</h4>
            #{metadata.present? ? "<p class=\"card-metadata-#{style}\">#{metadata}</p>" : ''}
            #{body_html}
            <a href="#{url}" class="card-link-#{style}">#{link_text}</a>
          </div>
        </div>
      HTML
    else
      # Small style: image, title, metadata, link (no excerpt)
      <<~HTML
        <div class="card post-link-#{style}">
          #{image.present? ? "<img src=\"#{image}\" alt=\"#{title}\" class=\"card-image\" data-sizes=\"(min-width: 768px) 300px, 100vw\">" : ''}
          <div class="card-content">
            <h4 class="card-title-#{style}">#{title}</h4>
            #{metadata.present? ? "<p class=\"card-metadata-#{style}\">#{metadata}</p>" : ''}
            <a href="#{url}" class="card-link-#{style}">#{link_text}</a>
          </div>
        </div>
      HTML
    end
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

  # FORMS

  def process_forms(content, preview: false)
    content.gsub(/```form\r?\n(.*?)```/m) do
      yaml_content = $1

      begin
        form_config = YAML.safe_load(yaml_content)
        render_form(form_config)
      rescue => e
        Rails.logger.error "Form YAML parsing error: #{e.message}"
        ""
      end
    end
  end

  def render_form(config)
    form_type = config['for']
    button_text = config['button-text'] || config['button_text'] || default_button_text(form_type)

    case form_type
    when 'paid_content'
      text = config['text'] || 'This is premium content. Upgrade to continue reading.'
      button_text = config['button-text'] || config['button_text'] || 'Become a paid member'
      render_paid_content_form(text, button_text)
    when 'signup'
      upgrade_text = config['upgrade-button-text'] || config['upgrade_button_text']
      render_signup_form(button_text, upgrade_text)
    when 'signin'
      render_signin_form(button_text)
    when 'checkout'
      member_text = config['member-button-text'] || config['member_button_text'] || button_text
      non_member_text = config['non-member-button-text'] || config['non_member_button_text']
      render_checkout_form(member_text, non_member_text)
    when 'unsubscribe'  # ADD THIS
      render_unsubscribe_form(button_text)
    when 'donate'
      render_donate_form(button_text)
    else
      ""
    end
  rescue => e
    Rails.logger.error "Form rendering error: #{e.message}"
    ""
  end

  def default_button_text(form_type)
    {
      'signup' => 'Sign Up',
      'signin' => 'Sign In',
      'checkout' => 'Upgrade',
      'donate' => 'Donate'
    }[form_type] || 'Submit'
  end

  def render_donate_form(button_text)
    return "" unless SiteFeature.donations_enabled?

    currency = (StripeConfig.current.currency.presence || "usd").upcase

    # Buttons render with bare amounts; the donate-form Stimulus
    # controller hydrates them with localized currency labels on
    # connect. This avoids a flash of wrong-currency symbols on
    # non-USD sites.
    presets = SiteFeature.donation_amounts.map do |amt|
      <<~HTML.strip
        <button type="button"
                class="donate-preset"
                data-donate-form-target="preset"
                data-action="click->donate-form#select"
                data-amount="#{amt}">#{amt}</button>
      HTML
    end.join("\n      ")

    <<~HTML
      <form action="/donate"
            method="post"
            class="donate-form"
            data-controller="donate-form"
            data-donate-form-currency-value="#{currency}"
            data-turbo="false">
        <input type="hidden" name="authenticity_token" value="#{form_authenticity_token}">
        <div class="donate-presets">
          #{presets}
        </div>
        <div class="form-field">
          <label for="donate_amount">Amount (#{currency})</label>
          <input type="text"
                 name="amount"
                 id="donate_amount"
                 data-donate-form-target="input"
                 inputmode="decimal"
                 placeholder="0.00"
                 required
                 pattern="\\d+(\\.\\d{1,3})?">
        </div>
        <button type="submit" class="donate-button btn-primary">#{button_text}</button>
      </form>
    HTML
  end

  def render_unsubscribe_form(button_text)
    # Token will be in URL, form will POST to same path
    <<~HTML
      <form action="" method="post" class="unsubscribe-form">
        <input type="hidden" name="authenticity_token" value="#{form_authenticity_token}">
        <button type="submit" class="unsubscribe-button btn-destructive">#{button_text}</button>
      </form>
    HTML
  end

  def render_paid_content_form(text, button_text)
    # This will act as a content gate - everything after this is paid
    <<~HTML
      <!-- PAID_CONTENT_GATE -->
      <div class="paid-content-gate">
        <p class="paywall-message">#{text}</p>
        <a href="/upgrade" class="upgrade-button">#{button_text}</a>
      </div>
    HTML
  end

  def render_signup_form(button_text, upgrade_button_text = nil)
    # Check if payments are actually enabled
    payments_enabled = SiteConfig.feature('members', 'payments.enabled')
    payments_enabled = (payments_enabled == true || payments_enabled == 'true')

    # Only show upgrade button if payments are enabled AND text is provided
    upgrade_button = if upgrade_button_text.present? && payments_enabled
      <<~HTML
        <button type="submit" formaction="/signup_and_checkout" class="signup-button signup-button-upgrade btn-primary">#{upgrade_button_text}</button>
      HTML
    else
      ""
    end

    <<~HTML
      <form action="/signup" method="post" class="signup-form">
        <input type="hidden" name="authenticity_token" value="#{form_authenticity_token}">

        <div class="form-field">
          <label for="member_name">Name</label>
          <input type="text" name="member[name]" id="member_name" required>
        </div>

        <div class="form-field">
          <label for="member_email">Email</label>
          <input type="email" name="member[email]" id="member_email" required>
        </div>

        <button type="submit" class="signup-button btn-outline">#{button_text}</button>
        #{upgrade_button}
      </form>
    HTML
  end

  def render_signin_form(button_text = 'Send Magic Link')
    <<~HTML
      <form action="/signin" method="post" class="signin-form">
        <input type="hidden" name="authenticity_token" value="#{form_authenticity_token}">

        <div class="form-field">
          <label for="member_email">Email</label>
          <input type="email" name="member[email]" id="member_email" required>
        </div>

        <button type="submit" class="signin-button">#{button_text}</button>
      </form>
    HTML
  end

  def render_checkout_form(member_button_text, non_member_button_text = nil)
    if non_member_button_text.blank?
      return <<~HTML
        <form action="/checkout" method="post" class="upgrade-form checkout-form" data-turbo="false">
          <input type="hidden" name="authenticity_token" value="#{form_authenticity_token}">
          <button type="submit" class="upgrade-button btn-primary">#{member_button_text}</button>
        </form>
      HTML
    end

    <<~HTML
      <div class="checkout-form-wrapper MEMBER_STATUS_PLACEHOLDER">
        <form action="/checkout" method="post" class="upgrade-form member-checkout checkout-form" data-turbo="false">
          <input type="hidden" name="authenticity_token" value="#{form_authenticity_token}">
          <button type="submit" class="upgrade-button btn-primary">#{member_button_text}</button>
        </form>

        <div class="non-member-checkout">
          <a href="/sign-up" class="upgrade-button btn-primary" data-turbo="false">#{non_member_button_text}</a>
        </div>
      </div>
    HTML
  end

  def form_authenticity_token
    # You might need to pass this in from the view context
    # For now, return a placeholder that will be replaced in the view
    "AUTHENTICITY_TOKEN_PLACEHOLDER"
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

  # BUTTONS

  def process_buttons(content, preview: false)
    # Pattern to match button blocks
    button_pattern = /```button\r?\n(.*?)```/m

    # Find all button blocks with their positions
    buttons = []
    content.scan(button_pattern) do |match|
      config_text = match[0]
      start_pos = $~.begin(0)
      end_pos = $~.end(0)

      begin
        config = parse_button_config(config_text)
        buttons << {
          config: config,
          start_pos: start_pos,
          end_pos: end_pos,
          match: $~
        }
      rescue => e
        Rails.logger.error "Button parsing error: #{e.message}"
      end
    end

    return content if buttons.empty?

    # Group consecutive buttons (no blank lines between)
    groups = []
    current_group = [buttons.first]

    buttons.each_cons(2) do |prev, curr|
      # Check if there's a blank line between these buttons
      text_between = content[prev[:end_pos]...curr[:start_pos]]

      if text_between =~ /\n\s*\n/
        # Blank line found - start new group
        groups << current_group
        current_group = [curr]
      else
        # No blank line - same group
        current_group << curr
      end
    end
    groups << current_group

    # Render each group
    result = content.dup
    offset = 0

    groups.each do |group|
      # Build context for button renderer
      context = {
        current_product: (self.is_a?(Product) ? self : nil),
        authenticated: preview
      }

      if group.length > 1
        # Multiple consecutive buttons - render as variant list
        skus = group.map { |b| b[:config]['sku'] }.compact
        if skus.length > 1
          renderer = ProductButtonRenderer.new({'skus' => skus}, context)
          rendered = renderer.render_variant_list
        else
          # Fall back to individual rendering if no SKUs
          rendered = group.map do |btn|
            ProductButtonRenderer.render(btn[:config], context)
          end.join("\n")
        end
      else
        # Single button - render normally
        rendered = ProductButtonRenderer.render(group.first[:config], context)
      end

      # Replace in result
      first_btn = group.first
      last_btn = group.last
      original_text = content[first_btn[:start_pos]...last_btn[:end_pos]]

      result.sub!(original_text, rendered)
    end

    result
  end

  def parse_button_config(config_text)
    config = {}
    config_text.each_line do |line|
      if line =~ /^\s*(\w+):\s*(.+)$/
        key = $1.strip
        value = $2.strip
        config[key] = value
      end
    end
    config
  end
end
