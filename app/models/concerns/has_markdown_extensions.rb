module HasMarkdownExtensions
  extend ActiveSupport::Concern

  # `sizes` for product-grid card images — mirrors the default theme's
  # .product-grid breakpoints so the browser fetches a card-sized variant
  # (small/medium) instead of assuming a full-width slot. See the grid
  # render in render_product_grid.
  PRODUCT_GRID_IMAGE_SIZES =
    "(min-width: 901px) 220px, (min-width: 769px) 30vw, (min-width: 401px) 45vw, 100vw".freeze

  def to_html(preview: false, context: nil, static: false)
    # Store context for use by form renderers
    @render_context = context

    # Store the static flag so downstream helpers (e.g. show_paid_indicator?)
    # can suppress dynamic-only affordances without threading the flag
    # through every render_* method signature.
    @rendering_static = static

    # In static-site mode, strip dynamic blocks that require a Rails
    # backend (forms, paywalls, product buttons). Done before any other
    # processing so downstream renderers never see them.
    source = if static
      content.to_s
             .gsub(/```form\r?\n.*?```/m, "")
             .gsub(/```button\r?\n.*?```/m, "")
    else
      content
    end

    # Step 1: Convert backtick fenced code blocks to HTML
    code_blocks = {}
    counter = 0

    # Handle 4+ backticks first (allow optional whitespace after language)
    processed_content = source.gsub(/````+(\w*)\s*\r?\n(.*?)````+/m) do
      lang = $1.empty? ? "text" : $1
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
      if [ "collection", "card", "gallery", "form", "button", "search" ].include?(lang)
        next $~.to_s
      end

      token = "CODE_BLOCK_PLACEHOLDER_#{counter}_END"
      code_blocks[token] = if lang == "poetry"
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
    processed_content = processed_content.gsub("||", "PULLQUOTE_SPLIT_END")

    # Process galleries, collections, cards, etc.
    processed_content = process_auto_galleries(processed_content)
    processed_content = process_galleries(processed_content, preview: preview)
    processed_content = process_collections(processed_content, preview: preview)
    processed_content = process_search(processed_content)
    processed_content = process_cards(processed_content, preview: preview)
    processed_content = process_forms(processed_content, preview: preview)
    processed_content = process_buttons(processed_content, preview: preview)
    processed_content = process_image_captions(processed_content)
    processed_content = process_strikethrough(processed_content)
    processed_content = escape_inline_pipes(processed_content)

    # Convert to HTML with Kramdown. hard_wrap only takes effect under the GFM
    # parser, so opting into soft line breaks switches to GFM (a superset that
    # also enables e.g. bare-URL autolinking); the default is standard kramdown.
    soft_breaks = soft_line_breaks?
    html = Kramdown::Document.new(
      processed_content,
      input: soft_breaks ? "GFM" : "kramdown",
      footnote_backlink: "",
      footnote_backlinks_inline: true,
      hard_wrap: soft_breaks
    ).to_html

    # Restore code blocks (now as HTML)
    code_blocks.each do |token, html_code|
      html.gsub!(token, html_code)
    end

    # Restore pullquote splits
    html.gsub!("PULLQUOTE_SPLIT_END", "||")

    # Swap search-trigger icon placeholders for the inline SVG AFTER Kramdown
    # (Kramdown mangles inline SVG, so triggers carry a token instead).
    html.gsub!(SEARCH_ICON_TOKEN, search_icon_svg) if html.include?(SEARCH_ICON_TOKEN)

    # Add footnote backlinks
    html = add_footnote_backlinks(html)

    # Process collection grids
    html = CollectionGridProcessor.process(html)

    # Merge floated pullquotes
    html = merge_floated_pullquotes(html)

    # Process images to make them responsive
    html = process_responsive_images(html)

    # Keep content off ids that belong to injected third-party mount points.
    html = reserve_mount_ids(html)

    html.html_safe
  ensure
    # Clear render context to prevent data leaking between requests
    @render_context = nil
    @rendering_static = nil
  end

  # IDs that belong to injected third-party mount points and must never be
  # claimed by content. kramdown's auto_ids turns a heading (or collection-item
  # title) named e.g. "Snipcart" into id="snipcart", which then collides with
  # Snipcart's cart container (<div id="snipcart">) — the widget mounts into the
  # heading and wipes it out. Rewrite any such content id to a namespaced form
  # so the heading stays anchorable without clobbering the mount. Extend the
  # list as other embeds reserve their own ids.
  RESERVED_MOUNT_IDS = %w[snipcart].freeze

  def reserve_mount_ids(html)
    RESERVED_MOUNT_IDS.reduce(html) do |acc, reserved|
      acc.gsub(/(\sid=["'])#{Regexp.escape(reserved)}(["'])/) do
        "#{Regexp.last_match(1)}#{reserved}-section#{Regexp.last_match(2)}"
      end
    end
  end

  # Media extensions that an `![](…)` embed should render as a native
  # HTML5 player rather than an image. Kept broad but conservative to
  # widely browser-supported container/codec combos.
  AUDIO_EMBED_EXTENSIONS = %w[.mp3 .m4a .aac .ogg .oga .wav .flac].freeze
  VIDEO_EMBED_EXTENSIONS = %w[.mp4 .m4v .webm .ogv .mov].freeze

  def render_audio_embed(src, alt)
    label = alt.to_s.strip
    aria = label.empty? ? "" : %( aria-label="#{escape_html(label)}")
    fallback = %(Your browser does not support the audio element. <a href="#{escape_html(src)}">Download the audio</a>.)
    %(<audio class="audio-embed" controls preload="metadata" src="#{escape_html(src)}"#{aria}>#{fallback}</audio>)
  end

  def render_video_embed(src, alt)
    label = alt.to_s.strip
    aria = label.empty? ? "" : %( aria-label="#{escape_html(label)}")
    fallback = %(Your browser does not support the video element. <a href="#{escape_html(src)}">Download the video</a>.)
    %(<video class="video-embed" controls preload="metadata" src="#{escape_html(src)}"#{aria}>#{fallback}</video>)
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
                "(min-width: 1200px) 1200px, 100vw"  # Default for non-gallery images
      end

      # Extract other attributes...
      alt = if pre_attrs =~ /alt=["']([^"']+)["']/i || post_attrs =~ /alt=["']([^"']+)["']/i
              $1
      else
              ""
      end

      css_class = if pre_attrs =~ /class=["']([^"']+)["']/i || post_attrs =~ /class=["']([^"']+)["']/i
                    $1
      else
                    ""
      end

      # Obsidian-style media embeds: `![label](/path/file.mp3)` renders a
      # native player in place instead of a broken <img>. Extensionless
      # native controls mean it works with no JS and is styleable via the
      # `audio`/`video` element selectors.
      ext = File.extname(src).downcase
      next render_audio_embed(src, alt) if AUDIO_EMBED_EXTENSIONS.include?(ext)
      next render_video_embed(src, alt) if VIDEO_EMBED_EXTENSIONS.include?(ext)

      next match_str unless ImageVariantGenerator::IMAGE_EXTENSIONS.include?(ext)

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
    lang_class = language.empty? ? "" : " class=\"language-#{CGI.escapeHTML(language)}\""
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
      line.gsub(/\|/, "&#124;")
    end.join("\n")
  end

  def add_footnote_backlinks(html)
    doc = Nokogiri::HTML::DocumentFragment.parse(html)

    # Find all footnote list items
    footnotes = doc.css(".footnotes ol li")

    footnotes.each_with_index do |li, index|
      footnote_id = li["id"] # e.g., "fn:1"
      next unless footnote_id

      # Extract the footnote number/name
      ref_id = footnote_id.sub("fn:", "fnref:")
      number = index + 1

      # Create backlink styled as a number
      backlink = Nokogiri::XML::Node.new("a", doc)
      backlink["href"] = "##{ref_id}"
      backlink["class"] = "footnote-backlink-number"
      backlink["role"] = "doc-backlink"
      backlink["aria-label"] = "Return to reference #{number}"
      backlink.content = "#{number}."

      # Insert at the very beginning of the <li>
      li.prepend_child(backlink)
      li.prepend_child(Nokogiri::XML::Text.new(" ", doc)) # Add space after number
    end

    doc.to_html
  end

  # GALLERIES

  def process_auto_galleries(markdown)
    lines = markdown.split("\n")
    result = []
    consecutive_images = []
    inside_fenced_block = false
    inside_footnote = false

    # Flush the pending image buffer as either a gallery block (2+) or a
    # single passthrough (1), then reset. Used wherever we leave image
    # collecting — entering/exiting fenced blocks and footnote defs.
    flush = lambda do
      if consecutive_images.length >= 2
        result << "```gallery"
        result.concat(consecutive_images)
        result << "```"
      elsif consecutive_images.length == 1
        result.concat(consecutive_images)
      end
      consecutive_images = []
    end

    lines.each do |line|
      # Track if we're inside a fenced code block
      if line.strip =~ /^```/
        inside_fenced_block = !inside_fenced_block

        # Flush any accumulated images before entering a block
        flush.call if inside_fenced_block

        result << line
        next
      end

      # Skip auto-gallery processing inside fenced blocks
      if inside_fenced_block
        result << line
        next
      end

      # Footnote definition tracking. A `[^N]:` line opens a footnote
      # definition; subsequent continuation lines (4+ space indent or
      # blank) belong to the footnote. A non-blank, non-indented line
      # closes it. We must NOT auto-wrap footnote images in a gallery
      # fence at column 0 — doing so breaks the 4-space continuation
      # indent that kramdown relies on to keep the lines inside the
      # footnote, which would silently eject those images (and any
      # following indented content) into the article body.
      if line =~ /^\[\^[^\]]+\]:/
        flush.call
        inside_footnote = true
        result << line
        next
      end

      if inside_footnote
        if line.strip.empty? || line =~ /^\s{4,}/
          # Continuation line — pass through verbatim, don't collect.
          result << line
          next
        end
        # Non-indented, non-blank line → footnote definition ends.
        inside_footnote = false
        # Fall through so the line is processed normally below.
      end

      # Check if this line is an image (with optional caption)
      if line.strip =~ /^!\[([^\]]*)\]\(([^)]+)\)\s*(?:\(\*([^*]+)\*\))?$/
        consecutive_images << line
      else
        # Not an image - process any accumulated images
        flush.call
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

  # Replace every fenced roe-anji block of the given language with the
  # output of `renderer.(body, *)`, preserving any leading whitespace on
  # the fence line. Without this, a ```gallery fence indented 4 spaces
  # inside a footnote definition gets replaced with column-0 HTML —
  # which breaks kramdown's 4-space continuation rule and silently
  # ejects the block (and any following indented content) out of the
  # footnote into the article body.
  def replace_fenced_blocks(markdown, lang)
    pattern = /^( *)```#{lang}\r?\n(.*?)```/m
    markdown.gsub(pattern) do |match|
      indent   = Regexp.last_match(1)
      body     = Regexp.last_match(2)
      rendered = yield(body)
      next rendered if indent.empty?

      rendered.lines.map { |line| line.strip.empty? ? line : "#{indent}#{line}" }.join
    end
  end

  def process_galleries(markdown, preview: false)
    index = -1
    replace_fenced_blocks(markdown, "gallery") do |body|
      index += 1
      render_gallery(body, preview: preview, index: index)
    end
  end

  # Converts image+caption syntax into a <figure>/<figcaption> block.
  #
  # Syntax:  ![alt](/path.jpg)(*Caption text*)
  #
  # Runs before Kramdown so the raw HTML block is passed through
  # unchanged. The image is rendered via ResponsiveImageRenderer so
  # it gets the same srcset/picture treatment as uncaptioned images.
  def process_image_captions(markdown)
    markdown.gsub(/!\[([^\]]*)\]\(([^)]+)\)\(\*([^*]+)\*\)/) do
      alt     = $1
      src     = $2.strip
      caption = $3.strip

      img_html = if ImageVariantGenerator::IMAGE_EXTENSIONS.include?(File.extname(src).downcase)
        ResponsiveImageRenderer.render(src, alt: alt)
      else
        "<img src=\"#{src}\" alt=\"#{CGI.escapeHTML(alt)}\">"
      end

      caption_html = Kramdown::Document.new(caption, input: "GFM").to_html.strip
                                        .gsub(%r{\A<p>(.*)</p>\z}m, '\1')

      "<figure>#{img_html}<figcaption>#{caption_html}</figcaption></figure>"
    end
  end

  # Fenced-gallery directives understood at the top/bottom of a ```gallery```
  # block (a `key: value` line that isn't a markdown image). Whitelisted so
  # stray "Word: text" lines stay content, not config.
  GALLERY_DIRECTIVES = %w[slideshow caption aspect_ratio].freeze

  def render_gallery(content, preview: false, index: 0)
    config, image_rows = parse_gallery(content)
    return (preview ? "<!-- Empty gallery -->" : "") if image_rows.flatten.empty?

    ratio_class = gallery_ratio_class(config["aspect_ratio"])

    body =
      if truthy_directive?(config["slideshow"])
        render_gallery_carousel(image_rows.flatten, index, ratio_class)
      else
        render_gallery_grid(image_rows, index, ratio_class)
      end

    body = wrap_gallery_caption(body, config["caption"])

    # {::nomarkdown} passes the raw HTML through kramdown untouched; the
    # later process_responsive_images sweep turns each <img data-sizes> into
    # a responsive <picture> (grid thumbs get small/medium variants, the
    # zoom overlay's data-sizes="100vw" pulls the largest).
    [ "", "{::nomarkdown}", body, "{:/nomarkdown}", "" ].join("\n")
  end

  # A gallery-level `caption:` directive wraps the whole gallery in a
  # <figure> with a single <figcaption> — a caption for the gallery as a
  # whole, distinct from the per-image `(*caption*)` figcaptions. The text
  # runs through kramdown (like image captions) so inline markdown works,
  # then the wrapping <p> is stripped for a clean inline figcaption. The
  # figcaption sits outside the .gallery div so it never trips the
  # `.gallery figcaption` / `.gallery-carousel:has(figcaption)` rules meant
  # for per-image captions.
  def wrap_gallery_caption(body, caption)
    return body if caption.blank?

    html = Kramdown::Document.new(caption.strip, input: "GFM").to_html.strip
                            .gsub(%r{\A<p>(.*)</p>\z}, '\1')
    %(<figure class="gallery-figure">#{body}<figcaption class="gallery-caption">#{html}</figcaption></figure>)
  end

  # Split a gallery body into [config, image_rows]. Directive lines are
  # pulled out first; the rest is grouped into rows by blank lines (blank
  # line = new grid row), each row scanned for `![alt](src) (*caption*)`.
  def parse_gallery(content)
    config = {}
    image_lines = []

    content.to_s.each_line do |line|
      m = line.match(/\A\s*([a-z_]+)\s*:\s*(.+?)\s*\z/i)
      if m && line !~ /!\[/ && GALLERY_DIRECTIVES.include?(m[1].downcase)
        config[m[1].downcase] = m[2]
      else
        image_lines << line
      end
    end

    rows = image_lines.join.split(/\n\s*\n/).map(&:strip).reject(&:empty?)
    image_rows = rows.map { |row| scan_gallery_images(row) }.reject(&:empty?)
    [ config, image_rows ]
  end

  def scan_gallery_images(row)
    images = []
    row.scan(/!\[([^\]]*)\]\(([^)]+)\)\s*(?:\(\*(.*?)\*\))?/) do
      images << { alt: $1, src: $2, caption: $3&.strip }
    end
    images
  end

  def truthy_directive?(value)
    %w[true yes 1 on].include?(value.to_s.strip.downcase)
  end

  # `aspect_ratio: square` (or original/cinema/tv/…) becomes a
  # `gallery-ratio-<value>` class on the .gallery container so a theme can set
  # the image aspect-ratio however it likes — no fixed whitelist, just add the
  # matching CSS. The value is author content, so keep only a safe CSS-token
  # subset ([a-z0-9-]); anything empty or unusable yields no class.
  def gallery_ratio_class(value)
    slug = value.to_s.strip.downcase.gsub(/[^a-z0-9-]/, "")
    "gallery-ratio-#{slug}" unless slug.empty?
  end

  # When on (site.yml `soft_line_breaks: true`), a single newline renders as a
  # <br> — no trailing-two-spaces needed. Off by default (standard Markdown).
  def soft_line_breaks?
    value = SiteConfig.get("soft_line_breaks")
    value == true || value == "true"
  end

  # Grid: blank-line rows, up to 3 columns each. Every image is a zoomable
  # .gallery-item; the matching :target overlays are collected and appended
  # once at the end of the gallery.
  def render_gallery_grid(image_rows, index, ratio_class = nil)
    out = +%(<div class="#{[ "gallery", ratio_class ].compact.join(' ')}">)
    overlays = +""
    item = 0

    image_rows.each do |images|
      col_count = [ images.length, 3 ].min
      sizes = gallery_grid_sizes(col_count)
      out << %(<div class="gallery-row gallery-col-#{col_count}">)
      images.each do |img|
        anchor = "gz-#{index}-#{item}"
        out << gallery_item_html(img, anchor, sizes)
        overlays << gallery_overlay_html(img, anchor)
        item += 1
      end
      out << "</div>"
    end

    out << overlays << "</div>"
  end

  # Carousel: one scroll-snap track, image order preserved. CSS does the
  # scrolling/snapping; gallery.js adds arrows/dots as enhancement.
  def render_gallery_carousel(images, index, ratio_class = nil)
    sizes = "(min-width: 1024px) 75vw, 100vw"
    out = +%(<div class="#{[ "gallery", "gallery-carousel", ratio_class ].compact.join(' ')}" data-gallery-carousel><div class="gallery-track">)
    overlays = +""

    images.each_with_index do |img, i|
      anchor = "gz-#{index}-#{i}"
      out << gallery_item_html(img, anchor, sizes)
      overlays << gallery_overlay_html(img, anchor)
    end

    out << "</div>" << overlays << "</div>"
  end

  def gallery_item_html(img, anchor, sizes)
    # Native popover trigger — opens the matching [popover] overlay in the
    # browser's top layer. No JS, no URL hash (so no Turbo conflict and no
    # scroll jump); Esc and click-outside dismiss it for free.
    link = %(<button type="button" class="gallery-zoom-link" popovertarget="#{anchor}" aria-label="View larger image">) +
           %(<img src="#{escape_html(img[:src])}" alt="#{escape_html(img[:alt])}" data-sizes="#{sizes}">) +
           "</button>"
    if img[:caption].present?
      caption = Kramdown::Document.new(img[:caption], input: "GFM").to_html.strip.gsub(%r{\A<p>(.*)</p>\z}, '\1')
      %(<figure class="gallery-item">#{link}<figcaption>#{caption}</figcaption></figure>)
    else
      %(<div class="gallery-item">#{link}</div>)
    end
  end

  # CSS-only lightbox via the native popover API: the overlay lives in the
  # top layer (immune to ancestor transforms/overflow), light-dismisses on
  # outside click, and closes on Esc — all without JS. data-sizes="100vw"
  # makes process_responsive_images serve the largest variant here.
  def gallery_overlay_html(img, anchor)
    alt = escape_html(img[:alt])
    %(<div id="#{anchor}" class="gallery-zoom" popover role="dialog" aria-label="#{alt}">) +
      %(<button type="button" class="gallery-zoom-close" popovertarget="#{anchor}" popovertargetaction="hide" aria-label="Close">&times;</button>) +
      %(<img class="gallery-zoom-image" src="#{escape_html(img[:src])}" alt="#{alt}" data-sizes="100vw" loading="lazy">) +
      "</div>"
  end

  def gallery_grid_sizes(col_count)
    case col_count
    when 1 then "(min-width: 1200px) 1200px, 100vw"
    when 2 then "(min-width: 1024px) 50vw, 100vw"
    else        "(min-width: 1024px) 33vw, (min-width: 768px) 50vw, 100vw"
    end
  end

  def escape_html(text)
    CGI.escapeHTML(text.to_s)
  end

  # COLLECTIONS

  def process_collections(markdown, preview: false)
    # Match fenced blocks with 'collection' language - handle both \n and \r\n
    replace_fenced_blocks(markdown, "collection") do |config_text|
      config = parse_collection_config(config_text)
      # A `search: true` collection renders a search icon (inside the
      # collection, beside the heading) — see render_collection/collection_header.
      render_collection(config)
    end
  end

  # The four content directories usable as a search scope; anything else in a
  # scope token is a post type.
  SEARCH_SCOPE_SOURCES = %w[posts pages documentation products].freeze

  # ```search block — renders a search icon that opens the global search
  # pre-scoped to the given filters:
  #   scope: documentation/products   (sources and/or post types)
  #   tags: ruby, -news               (include / exclude)
  def process_search(markdown)
    replace_fenced_blocks(markdown, "search") do |config_text|
      config = parse_collection_config(config_text)
      tokens = (config[:scope] || config[:source]).to_s.split(%r{[\s,/]+}).map(&:strip).reject(&:empty?)
      scope = {}
      sources = tokens & SEARCH_SCOPE_SOURCES
      post_types = tokens - SEARCH_SCOPE_SOURCES
      scope[:sources] = sources if sources.any?
      scope[:postTypes] = post_types if post_types.any?
      scope.merge!(parse_search_tag_scope(config[:tags]))
      search_trigger_html(scope)
    end
  end

  # Trigger for a collection with `search: true`; "" when not enabled.
  def collection_search_trigger(config)
    return "" unless truthy_directive?(config[:search])

    scope = {}
    base = (config[:source] || "posts").to_s.split("/").first
    scope[:sources] = [ base ] if SEARCH_SCOPE_SOURCES.include?(base)
    post_type = config[:post_type] || config[:"post-type"]
    scope[:postTypes] = [ post_type.to_s ] if post_type.present? && post_type != "all"
    scope.merge!(parse_search_tag_scope(config[:tags]))
    search_trigger_html(scope)
  end

  # tag string ("ruby, -news") → { tagsInclude:, tagsExclude: }
  def parse_search_tag_scope(tags_str)
    return {} if tags_str.blank?

    list = tags_str.to_s.split(",").map(&:strip).reject(&:empty?)
    include_tags = list.reject { |t| t.start_with?("-") }
    exclude_tags = list.select { |t| t.start_with?("-") }.map { |t| t[1..] }
    out = {}
    out[:tagsInclude] = include_tags if include_tags.any?
    out[:tagsExclude] = exclude_tags if exclude_tags.any?
    out
  end

  # A search icon that opens the global search overlay pre-scoped. The
  # search-trigger controller dispatches a `site-search:open` event with the
  # scope; the header site-search controller listens and opens.
  def search_trigger_html(scope)
    %(<button type="button" class="site-search-trigger" data-controller="search-trigger" ) +
      %(data-search-trigger-scope-value='#{CGI.escapeHTML((scope || {}).to_json)}' ) +
      %(data-action="search-trigger#open" aria-label="Search">#{search_trigger_icon}</button>)
  end

  # Placeholder emitted inside the trigger button; swapped for the inline SVG
  # after Kramdown runs (Kramdown mangles inline SVG mid-pipeline). Inlining
  # the SVG — rather than an <img> — lets the theme recolor it via currentColor.
  SEARCH_ICON_TOKEN = "SEARCHTRIGGERICONSVG".freeze

  def search_trigger_icon
    search_icon_svg.present? ? SEARCH_ICON_TOKEN : "Search"
  end

  # Raw contents of search.svg (memoized), or "" when absent. The site's own
  # copy at system/assets/images/ wins; otherwise fall back to the icon Roe
  # ships in app/assets/images/icons/ so the trigger has an icon out of the box.
  def search_icon_svg
    @search_icon_svg ||= begin
      site_path = File.join(RoeSitePaths::SITE_PATH, "system", "assets", "images", "search.svg")
      bundled   = Rails.root.join("app", "assets", "images", "icons", "search.svg").to_s
      path = File.exist?(site_path) ? site_path : bundled
      File.exist?(path) ? File.read(path).strip : ""
    end
  end

  # Collection heading row. When `search: true`, wrap the heading + trigger in
  # a raw header div (passes through Kramdown untouched) so the icon sits
  # beside the heading; otherwise keep the plain markdown/HTML heading.
  def collection_header(config, heading, markdown:)
    trigger = collection_search_trigger(config)
    has_heading = heading.present?

    if trigger.empty?
      return "" unless has_heading
      return markdown ? "## #{heading}" : "<h2>#{heading}</h2>"
    end

    parts = []
    parts << "<h2>#{heading}</h2>" if has_heading
    parts << trigger
    %(<div class="collection-header">#{parts.join}</div>)
  end

  def parse_collection_config(text)
    config = {}
    text.split("\n").each do |line|
      next if line.strip.empty?
      key, value = line.split(":", 2).map(&:strip)
      config[key.to_sym] = value if key && value
    end
    config
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

  def render_collection(config)
    heading = config[:heading]
    source = config[:source] || SiteConfig.default("collections", "default_source") || "posts"
    order_by = config[:order] || SiteConfig.default("collections", "default_order") || "date"
    tags = config[:tags]
    category = config[:category]
    podcast_key = config[:podcast]

    # Get post_type from config or default, treating 'all' as nil (no filter)
    post_type = config[:post_type]
    post_type = nil if post_type == "all"

    # Validate tags in dev — warn about tags that don't exist on the source
    tag_warning = ""
    if Rails.env.development? && tags.present?
      requested = tags.split(",").map(&:strip)
                      .reject { |t| t.start_with?("-") }  # ignore exclusions

      # Get existing tags based on source
      existing = case source
      when "products"
        Product.all_tags
      when "documentation"
        Documentation.all_tags("")
      when /^documentation\//
        Documentation.all_tags(source.sub("documentation/", ""))
      when "pages"
        # Pages don't have tags yet, skip validation
        []
      else
        # Default to posts
        Post.all_tags
      end

      unknown = requested.reject { |t| existing.include?(t) }
      if unknown.any?
        source_name = source == "products" ? "product" : "post"
        return dev_warning(
          "Unknown tag#{'s' if unknown.size > 1}",
          "#{unknown.map { |t| "'#{t}'" }.join(', ')} #{'does' if unknown.size == 1}#{'do' if unknown.size > 1} not exist on any #{source_name}.",
          "Existing tags: #{existing.any? ? existing.join(', ') : '(none yet)'}. " \
          "Add the tag to at least one #{source_name}'s metadata and it will show up in this collection."
        )
      end
    end

    # Validate post_type in dev — catches typos like 'articles' instead of 'article'
    if Rails.env.development? && post_type.present? && source == "posts"
      valid_types = Post.post_type_options
      unless valid_types.include?(post_type)
        return dev_warning(
          "Unknown post_type",
          "'#{post_type}' is not a recognised post type.",
          "Valid types: #{valid_types.join(', ')}"
        )
      end
    end

    # Get base collection
    items = case source
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
    when /^documentation\//
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
      if Rails.env.development?
        valid = %w[posts pages documentation documentation/roe products]
        return dev_warning("Unknown collection source",
          "'#{source}' is not a valid source.",
          "Valid sources: #{valid.join(', ')}")
      end
      []
    end

    # `related: true` — filter the source collection to items that
    # share a `related:` link with this document, in *either*
    # direction. Lets a doc/post/page render a "see also" block
    # without every pair having to declare each other:
    #
    #   # foo.md frontmatter:
    #   related:
    #     - "bar"
    #
    #   # bar.md frontmatter: (no `related:` needed)
    #
    #   # bar.md content:
    #   ```collection
    #   source: documentation
    #   related: true
    #   ```
    #
    # Bar's collection still shows foo because foo declared bar.
    # Forward items (this doc's own `related:` list) come first, in
    # the order they were declared (author-curated), followed by
    # back-link items (sources that declared this doc), deduped on
    # url_name and with self removed. The block's `order:` still
    # overrides — set it explicitly if you'd rather get a uniform
    # alphabetical / date / etc. sort across the union.
    #
    # Source-agnostic: works identically for docs, posts, pages,
    # products via the shared HasMetadata interface.
    related_filter = collection_truthy?(config[:related])
    if related_filter
      my_url_name      = url_name.to_s
      my_related_slugs = Array(metadata["related"]).map(&:to_s).reject(&:empty?)

      items_array = items.to_a
      by_slug     = items_array.index_by(&:url_name)

      # Forward: items I declare as related, in my declared order.
      forward = my_related_slugs.map { |slug| by_slug[slug] }.compact

      # Backward: items that declare *me* as related.
      backward = items_array.select do |item|
        Array(item.metadata["related"]).map(&:to_s).include?(my_url_name)
      end

      items = (forward + backward)
        .reject { |item| item.url_name == my_url_name } # drop self before dedup
        .uniq   { |item| item.url_name }                # forward wins on collision
    end

    # Apply paid content filter (before ordering!)
    items = CollectionMembersFilter.filter(items, config)

    # Apply ordering based on order parameter — unless we just
    # populated `items` from the curated `related:` list AND the
    # block didn't specify its own order, in which case the author's
    # frontmatter ordering is the right answer and we leave it
    # alone.
    unless related_filter && config[:order].blank?
      items = apply_collection_order(items, order_by)
    end

    # Apply offset and limit
    offset_value = config[:offset].to_i
    limit_value = config[:limit]
    default_limit = SiteConfig.default("collections", "default_limit") || 10
    show_more = config[:show_more] == "true" || config[:show_more] == true

    # Convert to array if needed
    items_array = items.is_a?(Array) ? items : items.to_a
    total_count = items_array.count

    # Apply offset (skip first N items)
    items_array = items_array[offset_value..-1] || [] if offset_value > 0

    if limit_value.to_s.downcase == "all"
      display_items = items_array
    elsif limit_value
      limit_int = limit_value.to_i
      display_items = items_array.take(limit_int)
    else
      display_items = items_array.take(default_limit)
    end

    # Render based on template, default to 'grid' for products, otherwise use configured default
    default_template = source == "products" ? "grid" : (SiteConfig.default("collections", "default_template") || "list")
    template = config[:template] || default_template
    list_markdown = render_template(display_items, template, config)

    # Build output with proper spacing.
    # The compact template produces raw HTML list items (to preserve the
    # .item-title span), so its wrapper must not carry markdown="1" —
    # Kramdown would re-process the HTML and strip the span tags.
    # All other templates emit Markdown/IAL and need markdown="1".
    output = []

    if template == "compact" || template == "glossary"
      output << "<div class=\"collection #{template}\">"
      output << collection_header(config, heading, markdown: false)
      output << list_markdown

      if show_more && total_count > display_items.count && source == "posts"
        show_more_text = config[:show_more_text] || "View all"
        collection_url = generate_collection_url(config)
        output << "<a href=\"#{collection_url}\" class=\"collection-more\">#{show_more_text}</a>"
      end

      output << "</div>"
    else
      output << "<div class=\"collection #{template}\" markdown=\"1\">"
      output << ""

      header = collection_header(config, heading, markdown: true)
      unless header.empty?
        output << header
        output << ""
      end

      output << list_markdown

      if show_more && total_count > display_items.count && source == "posts"
        show_more_text = config[:show_more_text] || "View all"
        collection_url = generate_collection_url(config)

        output << ""
        output << "[#{show_more_text}](#{collection_url})"
        output << "{: .collection-more}"
      end

      output << ""
      output << "</div>"
    end

    tag_warning + output.join("\n")
  end

  def apply_collection_order(items, order_by)
    case order_by
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
      # Alphabetical by title. In-memory sort so this works whether
      # `items` is an ActiveRecord relation (regular collections) or
      # a plain Array (which `related: true` produces after its
      # bidirectional dedup pass). Collection blocks operate on small
      # N already, so the cost over SQL ORDER BY is negligible.
      items.to_a.sort_by { |item| item.title.to_s.downcase }
    when "date"
      # Newest first (default). nil dates sort to the end via a
      # nil-safe sentinel — matches the NULLS LAST behaviour of the
      # previous SQL form.
      items.to_a.sort_by { |item| item.respond_to?(:date) && item.date ? item.date : Date.new(0) }.reverse
    when "date-asc"
      # Oldest first. nil dates sort to the end.
      items.to_a.sort_by { |item| item.respond_to?(:date) && item.date ? item.date : Date.new(9999) }
    else
      # Default to date descending — same as the explicit "date" case.
      items.to_a.sort_by { |item| item.respond_to?(:date) && item.date ? item.date : Date.new(0) }.reverse
    end
  end

  def render_template(items, template, config)
    case template
    when "grid"
      render_product_grid(items, config)
    when "compact"
      render_compact(items, config)
    when "glossary"
      render_glossary(items)
    when "links"
      render_links(items)
    when "full"
      render_full(items, config)
    when "list"
      render_list(items, config)
    else
      render_list(items, config)
    end
  end

  def render_list(items, config = {})
    show_author = collection_truthy?(config[:show_author])

    items.map do |item|
      output = []
      output << '<div class="collection-item" markdown="1">'
      output << ""

      # Title (linked) with optional lock icon
      title_html = decorate_title(item)
      output << "### [#{title_html}](#{item_path(item)})"
      output << "{: .item-title}"
      output << ""

      # Subtitle
      if item.respond_to?(:subtitle) && item.subtitle.present?
        output << "#{item.subtitle}"
        output << "{: .item-subtitle}"
        output << ""
      end

      # Meta row: date, optionally with " • author" appended
      date_str = item_date(item)
      author_str = show_author ? item_author(item) : nil
      if date_str || author_str
        parts = []
        parts << "<span class=\"item-date\">#{date_str}</span>" if date_str
        parts << "<span class=\"item-author\">#{author_str}</span>" if author_str
        output << parts.join(" • ")
        output << "{: .item-meta}"
        output << ""
      end

      output << "</div>"
      output << ""

      output.join("\n")
    end.join("\n")
  end

  # Image-on-the-right template. Includes everything from `list`, plus
  # excerpt and a featured image. show_author defaults to TRUE for this
  # template (opposite of list); pass `show_author: false` to suppress.
  # show_excerpt also defaults to true.
  #
  # Media indicators (play / headphones for video / audio / podcast posts)
  # are added next to the title by decorate_title — same as every other
  # collection template. No icon overlay on the image.
  def render_full(items, config = {})
    show_author = collection_truthy?(config[:show_author], default: true)
    show_excerpt = collection_truthy?(config[:show_excerpt], default: true)

    items.map do |item|
      image_url = item.respond_to?(:image) ? item.image : nil
      has_image = image_url.present?
      alt = (item.title || "").to_s.gsub('"', "&quot;")

      output = []
      output << '<div class="collection-item">'

      if has_image
        output << %Q(  <a class="item-image" href="#{item_path(item)}">)
        output << "    #{ResponsiveImageRenderer.render(image_url, alt: alt)}"
        output << "  </a>"
      end

      output << '  <div class="item-body" markdown="1">'
      output << ""

      title_html = decorate_title(item)
      output << "### [#{title_html}](#{item_path(item)})"
      output << "{: .item-title}"
      output << ""

      if item.respond_to?(:subtitle) && item.subtitle.present?
        output << "#{item.subtitle}"
        output << "{: .item-subtitle}"
        output << ""
      end

      if show_excerpt && item.respond_to?(:excerpt) && item.excerpt.present?
        output << item.excerpt.to_s
        output << "{: .item-excerpt}"
        output << ""
      end

      date_str = item_date(item)
      author_str = show_author ? item_author(item) : nil
      if date_str || author_str
        parts = []
        parts << "<span class=\"item-date\">#{date_str}</span>" if date_str
        parts << "<span class=\"item-author\">#{author_str}</span>" if author_str
        output << "  #{parts.join(" • ")}"
        output << "  {: .item-meta}"
        output << ""
      end

      output << "  </div>"
      output << "</div>"
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
      %Q(<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 16.1328 15.7715"><g><rect height="15.7715" opacity="0" width="16.1328" x="0" y="0"/>
        <path d="M7.88086 15.7617C12.2363 15.7617 15.7715 12.2363 15.7715 7.88086C15.7715 3.52539 12.2363 0 7.88086 0C3.53516 0 0 3.52539 0 7.88086C0 12.2363 3.53516 15.7617 7.88086 15.7617ZM7.88086 14.2773C4.3457 14.2773 1.49414 11.416 1.49414 7.88086C1.49414 4.3457 4.3457 1.48438 7.88086 1.48438C11.416 1.48438 14.2773 4.3457 14.2773 7.88086C14.2773 11.416 11.416 14.2773 7.88086 14.2773Z" fill="currentColor" fill-opacity="0.85"/>
        <path d="M6.46484 10.8691L10.8105 8.31055C11.1523 8.125 11.1426 7.64648 10.8105 7.46094L6.46484 4.90234C6.12305 4.69727 5.6543 4.85352 5.6543 5.24414L5.6543 10.5273C5.6543 10.918 6.08398 11.1035 6.46484 10.8691Z" fill="currentColor" fill-opacity="0.85"/>
       </g></svg>)
    when :headphones
      %Q(<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 16.1328 15.7715">
       <g>
        <rect height="15.7715" opacity="0" width="16.1328" x="0" y="0"/>
        <path d="M7.88086 15.7617C12.2363 15.7617 15.7715 12.2363 15.7715 7.88086C15.7715 3.52539 12.2363 0 7.88086 0C3.53516 0 0 3.52539 0 7.88086C0 12.2363 3.53516 15.7617 7.88086 15.7617ZM7.88086 14.2773C4.3457 14.2773 1.49414 11.416 1.49414 7.88086C1.49414 4.3457 4.3457 1.48438 7.88086 1.48438C11.416 1.48438 14.2773 4.3457 14.2773 7.88086C14.2773 11.416 11.416 14.2773 7.88086 14.2773Z" fill="currentColor" fill-opacity="0.85"/>
        <path d="M3.71094 7.87109C3.71094 9.35547 4.0625 10.4199 4.64844 11.4355C4.82422 11.7188 5.14648 11.8066 5.44922 11.6406C5.73242 11.5039 5.82031 11.1523 5.6543 10.8398C5.16602 9.93164 4.88281 9.14062 4.88281 7.87109C4.88281 5.87891 6.07422 4.57031 7.88086 4.57031C9.69727 4.57031 10.9082 5.88867 10.9082 7.87109C10.9082 9.14062 10.625 9.94141 10.1074 10.8398C9.95117 11.1426 10.0391 11.4941 10.3223 11.6406C10.6152 11.8066 10.957 11.7188 11.123 11.4355C11.7188 10.3809 12.0703 9.32617 12.0703 7.87109C12.0703 5.20508 10.3906 3.4082 7.88086 3.4082C5.39062 3.4082 3.71094 5.19531 3.71094 7.87109ZM5.17578 11.2598C5.32227 11.7871 5.80078 12.0605 6.31836 11.8945C6.85547 11.748 7.11914 11.2891 6.96289 10.7617L6.42578 8.87695C6.26953 8.33984 5.81055 8.08594 5.2832 8.23242C4.75586 8.37891 4.48242 8.84766 4.63867 9.375ZM10.5957 11.2598L11.123 9.375C11.2793 8.83789 11.0254 8.37891 10.4883 8.23242C9.96094 8.08594 9.50195 8.33984 9.3457 8.87695L8.80859 10.7715C8.65234 11.2988 8.90625 11.748 9.45312 11.8945C9.98047 12.0508 10.4492 11.7871 10.5957 11.2598Z" fill="currentColor" fill-opacity="0.85"/>
       </g>
      </svg>)
    end
  end

  # Build the "date • author" meta line for collection items. Author is
  # only included when show_author is truthy AND the post (or site
  # config) actually has an author to show.
  def collection_item_meta(item, show_author: false)
    parts = []

    if item.respond_to?(:date) && item.date
      date = item.date
      # Handle both Date objects and strings
      if date.is_a?(String)
        begin
          date = Date.parse(date)
        rescue
          date = nil
        end
      end
      parts << date.strftime("%B %d, %Y") if date
    end

    if show_author
      author = item.metadata["author"].to_s.strip
      author = SiteConfig.get("author").to_s.strip if author.blank?
      parts << author if author.present?
    end

    parts.join(" • ")
  end

  def item_date(item)
    return nil unless item.respond_to?(:date) && item.date

    date = item.date
    if date.is_a?(String)
      begin
        date = Date.parse(date)
      rescue
        date = nil
      end
    end
    date&.strftime("%B %d, %Y")
  end

  def item_author(item)
    author = item.metadata["author"].to_s.strip
    author = SiteConfig.get("author").to_s.strip if author.blank?
    author.presence
  end

  # Collection-block options arrive as strings ("true"/"false") or as
  # parsed booleans depending on caller. Returns the boolean intent;
  # use `default:` to set what `nil` means.
  def collection_truthy?(val, default: false)
    return default if val.nil?
    val == true || val.to_s.downcase == "true"
  end

  def render_compact(items, config = {})
    show_author   = collection_truthy?(config[:show_author])
    show_date     = collection_truthy?(config[:show_date], default: true)
    show_subtitle = collection_truthy?(config[:show_subtitle], default: false)

    items_html = items.map do |item|
      date_str   = show_date ? item_date(item) : nil
      author_str = show_author ? item_author(item) : nil

      # Subtitle: explicit config override > item's subtitle field
      subtitle_str = if config[:subtitle].present?
        CGI.escapeHTML(config[:subtitle].to_s)
      elsif show_subtitle
        item.respond_to?(:subtitle) ? CGI.escapeHTML(item.subtitle.to_s.strip) : nil
      end

      meta_html = ""
      if date_str || author_str
        parts = []
        parts << "<span class=\"item-date\">#{date_str}</span>" if date_str
        parts << "<span class=\"item-author\">#{author_str}</span>" if author_str
        meta_html = " • #{parts.join(" • ")}"
      end

      subtitle_html = subtitle_str.present? ? " — <span class=\"item-subtitle\">#{subtitle_str}</span>" : ""

      title_html = decorate_title(item)
      link_html = "<a href=\"#{item_path(item)}\">#{title_html}</a>"
      "<li><span class=\"item-title\">#{link_html}</span>#{subtitle_html}#{meta_html}</li>"
    end

    "<ul>\n#{items_html.join("\n")}\n</ul>"
  end

  # Glossary template: renders definition-style entries with no links.
  # Each item shows its title as the term and subtitle as the definition,
  # with an optional excerpt for additional detail.
  #
  # Output structure:
  #   <dl class="glossary-list">
  #     <div class="glossary-entry">
  #       <dt class="item-title">Term</dt>
  #       <dd class="item-subtitle">Short definition</dd>
  #       <dd class="item-excerpt">Optional detail...</dd>  (when present)
  #     </div>
  #   </dl>
  def render_glossary(items)
    items_html = items.map do |item|
      title    = CGI.escapeHTML(item.title.to_s.presence || "Untitled")
      term_id  = item.title.to_s.downcase.gsub(/[^a-z0-9]+/, "-").sub(/^-+/, "").sub(/-+$/, "")
      subtitle = item.respond_to?(:subtitle) ? item.subtitle.to_s.strip : ""
      excerpt  = item.metadata["excerpt"].to_s.strip
      link     = item.metadata["link"].to_s.strip.presence

      title_content = link ? "<a href=\"#{CGI.escapeHTML(link)}\">#{title}</a>" : title

      html = "<div class=\"glossary-entry\">\n"
      html << "  <dt id=\"#{term_id}\" class=\"item-title\">#{title_content}</dt>\n"
      html << "  <dd class=\"item-subtitle\">#{CGI.escapeHTML(subtitle)}</dd>\n" if subtitle.present?
      html << "  <dd class=\"item-excerpt\">#{CGI.escapeHTML(excerpt)}</dd>\n" if excerpt.present?
      html << "</div>"
      html
    end

    "<dl class=\"glossary-list\">\n#{items_html.join("\n")}\n</dl>"
  end

  def render_links(items)
    items.map do |item|
      output = []
      output << '<div class="collection-item" markdown="1">'
      output << ""

      # Title (linked) with optional lock icon
      title_html = decorate_title(item)
      output << "### [#{title_html}](#{item_path(item)})"
      output << "{: .item-title}"
      output << ""

      # Subtitle
      if item.respond_to?(:subtitle) && item.subtitle.present?
        output << "#{item.subtitle}"
        output << "{: .item-subtitle}"
        output << ""
      end

      output << "</div>"
      output << ""

      output.join("\n")
    end.join("\n")
  end

  def render_product_grid(items, config)
    # Get currency symbol from store config
    currency_symbol = get_currency_symbol

    # Check if description should be shown
    show_description = config[:show_description] == "true" || config[:show_description] == true

    # Check if grouping is enabled
    groups_enabled = config[:groups] == "enabled" || config[:groups] == true

    # Get aspect ratio setting (default to 'auto')
    aspect_ratio = config[:aspect_ratio] || "auto"
    image_class = "img-#{aspect_ratio}"

    # Get grouped product settings
    grouped_config = SiteConfig.feature("store", "grouped_products") || {}
    grouped_button_text = grouped_config["button_text"].presence
    price_display_mode = grouped_config["price_display"] || "range"
    price_separator = grouped_config["price_separator"].presence || "-"

    # Group items by their group field if groups enabled, otherwise show all
    if groups_enabled
      # Group items by their group field
      grouped_items = items.group_by do |item|
        item.respond_to?(:group) && item.group.present? ? item.group : item.id
      end
    else
      # No grouping - each item is its own group
      grouped_items = items.map { |item| [ item.id, [ item ] ] }.to_h
    end

    output = []
    output << '<div class="product-grid">'

    grouped_items.each do |group_id, group_products|
      # Determine which product to display
      display_product = determine_display_product(group_products)
      next unless display_product

      # Check if this is a grouped product
      is_grouped = group_products.length > 1

      # Product image — detect missing/broken image in dev before rendering
      image_url = display_product.respond_to?(:image) ? display_product.image.presence : nil

      # An image is broken if: (a) blank/unset, or (b) points at a /media/
      # path that doesn't exist on disk.
      missing_file = image_url.present? &&
                     image_url.start_with?("/media/") &&
                     display_product.respond_to?(:missing_media_refs) &&
                     display_product.missing_media_refs.any? { |r| r[:field] == "image" }
      broken_image = image_url.blank? || missing_file

      if broken_image && Rails.env.development?
        variant_label = display_product.respond_to?(:variant) ? display_product.variant.presence : nil
        primary_flag  = display_product.respond_to?(:primary?) && display_product.primary?
        name_parts    = [ display_product.title.presence || "Untitled" ]
        name_parts   << variant_label if variant_label
        name_parts   << "primary" if is_grouped && primary_flag
        label         = name_parts.join(" • ")

        if image_url.blank?
          warning_title = is_grouped ? "No image on primary product" : "No product image"
          warning_msg   = "\"#{label}\" has no image set."
          warning_hint  = is_grouped ? "The primary variant controls the image shown in collections. Add an image or mark a different variant as primary." : "Add an image path to this product's front matter."
        else
          warning_title = is_grouped ? "Broken image on primary product" : "Broken product image"
          warning_msg   = "\"#{label}\" has image: #{image_url.inspect} but the file doesn't exist."
          warning_hint  = is_grouped ? "The primary variant controls the image shown in collections. Fix the image path or mark a different variant as primary." : "Check the image path in this product's front matter."
        end

        output << "  <div class=\"grid-item\">"
        output << dev_warning(warning_title, warning_msg, warning_hint)
        output << "  </div>"
        next
      end

      output << '  <div class="grid-item">'

      # Fallback for a missing product image. 404.png ships in the
      # install kit under site/system/assets/images/ and is served at
      # /system/images/ — NOT /media/, which only serves user uploads.
      image_url ||= "/system/images/404.png"

      output << %Q(    <div class="grid-item-image">)
      output << %Q(      <a href="#{item_path(display_product)}">)
      # Product grid columns (default theme .product-grid): 1 up to 400px,
      # 2 to 768px, 3 to 900px, then auto-fit minmax(200px) → ~200-330px
      # cards on desktop. Without an accurate `sizes` the browser assumes a
      # near-full-width slot and pulls large/xl for a ~220px card; this maps
      # each breakpoint to its real card width so it picks small/medium.
      output << "        #{ResponsiveImageRenderer.render(image_url, alt: (display_product.title || 'Product'), class: image_class, sizes: PRODUCT_GRID_IMAGE_SIZES)}"
      output << %Q(      </a>)
      output << %Q(    </div>)

      # Product title (linked)
      output << %Q(    <div class="grid-item-title">)
      output << %Q(      <a href="#{item_path(display_product)}">#{display_product.title || 'Untitled'}</a>)
      output << %Q(    </div>)

      # Show variants if grouped
      if is_grouped
        variants = group_products.map { |p| p.variant || "Standard" }.compact.join(", ")
        output << %Q(    <div class="grid-item-variants">(#{variants})</div>)
      end

      # Optional description
      if show_description && display_product.respond_to?(:description) && display_product.description.present?
        # Truncate to ~100 characters
        desc = display_product.description.length > 100 ? display_product.description[0..97] + "..." : display_product.description
        output << %Q(    <div class="grid-item-description">#{desc}</div>)
      end

      # Price and button
      output << '    <div class="grid-item-footer">'

      if is_grouped
        # Show price based on config setting
        prices = group_products.map { |p| p.price.to_f }.compact
        if prices.any?
          formatted_price = case price_display_mode
          when "lowest"
            "#{currency_symbol}#{sprintf('%.2f', prices.min)}"
          when "highest"
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
          output << %Q(      <a href="#{item_path(primary_for_link)}" class="btn-primary btn-grid">#{grouped_button_text}</a>)
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
          domain = SiteConfig.feature("store", "default_domain")
          validation_url = domain ? "https://#{domain}#{product_url}" : product_url

          output << %Q(      <button class="snipcart-add-item btn-primary btn-grid")
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

      output << "    </div>" # Close grid-item-footer
      output << "  </div>" # Close grid-item
    end

    output << "</div>" # Close product-grid
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
    currency = SiteConfig.feature("store", "currency") || "usd"
    case currency.downcase
    when "usd" then "$"
    when "eur" then "€"
    when "gbp" then "£"
    when "cad" then "CA$"
    when "aud" then "A$"
    when "jpy" then "¥"
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
    post_type = config[:post_type] unless config[:post_type] == "all"
    order = config[:order]
    source = config[:source] || "posts"  # ← ADD THIS
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
        positive_tags = tags.split(",").map(&:strip).reject { |t| t.start_with?("-") }
        segments << positive_tags.map(&:parameterize).join(",") if positive_tags.any?
      end

      "/collections/#{segments.join('/')}"
    else
      # No filters, no heading = general archive
      archive_page = Page.find_by("json_extract(metadata, '$.url_name') = ?", "archive")
      archive_page ? "/archive" : "/posts"
    end

    # Build query params (NEW)
    query_params = []

    # Always pass source if non-default
    query_params << "source=#{source}" if source != "posts"

    # Pass heading if it's a heading-based collection (so controller knows it's not a tag)
    query_params << "heading=#{CGI.escape(heading)}" if heading.present?

    # Add order if non-default
    query_params << "order=#{order}" if order.present? && order != "date"

    # Add podcast key if present
    query_params << "podcast=#{CGI.escape(podcast_key)}" if podcast_key.present?

    # Add exclude tags if present
    if tags.present?
      exclude_tags = tags.split(",").map(&:strip).select { |t| t.start_with?("-") }.map { |t| t.sub("-", "") }
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
    # Suppress the paid lock in static-site builds — without a member
    # session there's no upgrade flow to drive viewers toward, so the
    # icon is just visual noise.
    return false if @rendering_static
    return false unless item.metadata["audience"] == "paid"
    return false unless SiteConfig.feature_enabled?("members")

    # Always show indicator for paid content
    true
  end

  def paid_lock_icon
    '<svg class="paid-lock-icon" viewBox="0 0 16 16" fill="currentColor" width="18" height="18"><path d="M7.88 15.76c4.36 0 7.89-3.53 7.89-7.88 0-4.36-3.53-7.88-7.89-7.88C3.54 0 0 3.52 0 7.88c0 4.35 3.54 7.88 7.88 7.88zm0-1.48c-3.54 0-6.39-2.86-6.39-6.4 0-3.54 2.85-6.4 6.39-6.4 3.54 0 6.4 2.86 6.4 6.4 0 3.54-2.86 6.4-6.4 6.4z"/><path d="M5.12 10.89c0 .56.24.82.77.82h3.97c.52 0 .77-.26.77-.82V7.87c0-.51-.22-.77-.64-.81v-.86c0-1.45-.85-2.42-2.12-2.42-1.26 0-2.12.97-2.12 2.42v.86c-.42.04-.64.3-.64.82zm1.52-3.84V6.1c0-.88.49-1.46 1.23-1.46s1.24.58 1.24 1.46v.95z"/></svg>'
  end

  # Inline media indicator (play / headphones) sized to sit alongside a
  # title. Reuses render_media_icon's SVG paths but injects width/height
  # and a stable class so themes can style consistently with .paid-lock-icon.
  def title_media_icon(type)
    svg = render_media_icon(type)
    return nil unless svg
    # Collapse any newlines/extra whitespace — the :play SVG is multi-line
    # in the source, and Kramdown breaks markdown links when their text
    # contains a literal newline.
    svg = svg.gsub(/\s+/, " ").strip
    svg.sub("<svg ", '<svg class="title-media-icon" width="18" height="18" ')
  end

  # Decorate a collection item's title with any applicable indicators:
  # paid lock first (if shown), then a media-type icon (headphones for
  # audio, play for video/podcast-with-video). Returns plain title when
  # neither applies. The last word + icons share a nowrap span so they
  # don't break across lines.
  def decorate_title(item)
    title = item.title || "Untitled"
    icons = []

    media_type = collection_media_icon(item)
    icons << title_media_icon(media_type) if media_type

    icons << paid_lock_icon if show_paid_indicator?(item)

    return title if icons.empty?

    words = title.split(" ")
    last_word = words.pop || ""
    icon_html = icons.compact.join
    nowrap = %(<span style="white-space:nowrap">#{last_word}&nbsp;#{icon_html}</span>)
    words.empty? ? nowrap : "#{words.join(' ')} #{nowrap}"
  end

  # Kept for back-compat with any external callers; new code should use
  # decorate_title which handles paid + media in one pass.
  def title_with_paid_icon(title)
    words = title.split(" ")
    last_word = words.pop
    icon = paid_lock_icon
    nowrap = %(<span style="white-space:nowrap">#{last_word}&nbsp;#{icon}</span>)
    words.empty? ? nowrap : "#{words.join(' ')} #{nowrap}"
  end

  ## CARDS

  def process_cards(markdown, preview: false)
    replace_fenced_blocks(markdown, "card") do |config_text|
      config = parse_card_config(config_text)
      render_card(config, preview: preview)
    end
  end

  def parse_card_config(text)
    config = {}
    text.split("\n").each do |line|
      next if line.strip.empty?
      key, value = line.split(":", 2).map(&:strip)
      config[key.to_sym] = value if key && value
    end
    config
  end

  def render_card(config, preview: false)
    type = config[:type] || "pullquote"

    case type
    when "pullquote"
      render_pullquote(config)
    when "aside"
      render_aside(config, preview: preview)
    when "post-link"
      render_post_link(config, preview: preview)
    when "product-link"
      render_product_link(config, preview: preview)
    else
      preview ? "<!-- Unknown card type -->" : ""
    end
  end

  # A product-link is a live post-link card pointed at a product. post-link
  # already resolves products (find_post_by_slug → /store/<slug>, title,
  # excerpt, image), so we just alias `product:` → `post:` and give it a
  # product-appropriate default link text, then reuse render_post_link. Any
  # explicit override (title, image, link_text, …) still wins.
  def render_product_link(config, preview: false)
    cfg = config.dup
    cfg[:post] = cfg[:product] if cfg[:product].present? && cfg[:post].blank?
    cfg[:link_text] ||= SiteConfig.default("cards", "product-link")&.[]("default_link_text") || "View product →"
    # Products use `description`, posts use `excerpt` — same card slot. Map it,
    # and show it by default (all styles) unless explicitly turned off.
    cfg[:excerpt] = cfg[:description] if cfg[:description].present? && cfg[:excerpt].blank?
    cfg[:show_excerpt] = cfg[:show_description] if cfg.key?(:show_description)
    cfg[:show_excerpt] = "true" unless cfg.key?(:show_excerpt)
    render_post_link(cfg, preview: preview, kind: "product-link")
  end

  ### PULLQUOTE

  def render_pullquote(config)
    text = config[:text] || ""
    attribution = config[:attribution] || ""
    position = config[:position] || SiteConfig.default("cards", "pullquote")&.[]("default_position") || "center"

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
    output << "</div>"

    output.join("\n")
  end

  def merge_floated_pullquotes(html)
    doc = Nokogiri::HTML::DocumentFragment.parse(html)

    # Find all floated pullquotes (left or right position)
    floated_pullquotes = doc.css(".pullquote-left, .pullquote-right")

    floated_pullquotes.each do |pullquote|
      # Get the next sibling element
      next_element = pullquote.next_element

      # Check if it's a paragraph
      if next_element && next_element.name == "p"
        # Get the paragraph HTML
        para_html = next_element.inner_html

        # Check for manual split marker
        if para_html.include?("||")
          # Manual split - use the || marker
          parts = para_html.split("||", 2)
          first_half = parts[0].strip
          second_half = parts[1].strip
        else
          # Automatic split - use smart detection
          split_point = find_split_point(para_html)
          first_half = para_html[0...split_point].strip
          second_half = para_html[split_point..-1].strip
        end

        # Create a wrapper div to hold all three parts
        wrapper = Nokogiri::XML::Node.new("div", doc)
        wrapper["class"] = "pullquote-merge"

        # Create first paragraph
        first_p = Nokogiri::XML::Node.new("p", doc)
        first_p.inner_html = first_half

        # Create second paragraph
        second_p = Nokogiri::XML::Node.new("p", doc)
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

    sentence_end = plain_text[search_start..search_end]&.index(". ")

    if sentence_end
      # Find this position in the original HTML text
      search_start + sentence_end + 2
    else
      # Fallback: try to split at a space near middle
      space_pos = plain_text[middle..-1]&.index(" ")
      space_pos ? middle + space_pos : middle
    end
  end

  ### POST LINKS

  def render_post_link(config, preview: false, kind: "post-link")
    # If a post reference is provided, look it up and merge its data
    if config[:post].present?
      referenced_post = find_post_by_slug(config[:post])

      if referenced_post
        # Derive the public URL based on the record type
        record_url = case referenced_post
        when Page          then referenced_post.public_url
        when Product       then "/store/#{referenced_post.url_name}"
        when Documentation then "/documentation/#{referenced_post.url_name}"
        else "/posts/#{referenced_post.url_name}"
        end

        post_data = {
          title:               referenced_post.title || "Untitled",
          subtitle_from_record: referenced_post.metadata["subtitle"] || "",
          # Products carry `description`; posts/pages carry `excerpt`. Same slot.
          excerpt:             (referenced_post.is_a?(Product) ? referenced_post.description : referenced_post.metadata["excerpt"]).to_s,
          url:                 record_url
        }

        # Author and date are post-only — omit for pages, products, docs
        if referenced_post.is_a?(Post)
          post_data[:author] = referenced_post.author || ""
          post_data[:date]   = referenced_post.date
        end

        # Only add image if the record has one
        post_data[:image] = referenced_post.image if referenced_post.respond_to?(:image) && referenced_post.image.present?

        # Override with any explicitly provided values
        config = post_data.merge(config.except(:post))
      else
        # Record not found - render error card in preview, dev warning otherwise
        return render_error_card("Content not found: #{config[:post]}") if preview
        return dev_warning("Content not found",
          "No post, page, product, or documentation with slug '#{config[:post]}' exists.",
          "Check the url_name in the content's front matter.")
      end
    end

    style = config[:style] || "small"
    title = config[:title] || "Untitled"
    date_raw = config[:date] || ""
    excerpt = config[:excerpt] || ""

    # Subtitle: explicit override > record's subtitle field.
    # show_subtitle defaults to true so existing cards and non-post
    # records (pages, docs) show the subtitle without any config needed.
    # Set show_subtitle: false to suppress it entirely.
    show_subtitle = collection_truthy?(config[:show_subtitle], default: true)
    subtitle = if config[:subtitle].present?
      config[:subtitle]  # Explicit override in card config
    elsif show_subtitle
      config[:subtitle_from_record] || ""
    else
      ""
    end
    url = config[:url] || "#"
    link_text = config[:link_text] || SiteConfig.default("cards", "post-link")&.[]("default_link_text") || "Read full story →"

    # Whether the excerpt/description shows. Large shows it by default (existing
    # behaviour); small/medium only when explicitly enabled. product-link maps
    # its show_description onto this and defaults it on for all styles.
    show_excerpt = collection_truthy?(config[:show_excerpt], default: style == "large")

    # Author and date are only meaningful for posts. For pages, products,
    # and docs the keys were intentionally omitted from config above.
    is_post_record = referenced_post.nil? || referenced_post.is_a?(Post)

    # Author fallback chain (posts only): card config -> post metadata -> site config -> blank
    author = if !is_post_record
      ""  # Non-post records never show author
    elsif config[:author].present?
      config[:author]  # 1. Explicitly provided in card
    else
      SiteConfig.get("author") || ""  # 2. Site-wide fallback
    end

    # Handle image with priority:
    #   1. explicit `image:` in the card (including "none" → no image)
    #   2. referenced post's image (merged into config[:image] above
    #      via post_data when the post has one)
    #   3. SiteConfig "default_image" — ONLY for inline cards with no
    #      `post:` reference. If a `post:` resolved a real post that
    #      simply has no image, honor that (no fallback) — otherwise
    #      every image-less post would silently pick up the same
    #      generic default thumbnail, defeating the point of leaving
    #      the post's image field empty.
    image = if config.key?(:image)
      # Image key exists in config (either typed in the card or merged
      # in from the referenced post's metadata).
      if config[:image] == "none"
        nil  # Explicitly no image
      elsif config[:image].blank?
        Rails.logger.warn "Empty image value in post-link card for #{title}" if preview
        nil
      else
        config[:image]  # Explicit URL — user-provided or post-provided
      end
    elsif referenced_post
      # A post: reference resolved (we'd have returned an error card
      # earlier if it hadn't) but the post has no image — that's how
      # post_data ended up without an :image key. Respect that.
      nil
    else
      # Inline card, no post: reference, no explicit image: — fall
      # back to the site-wide default thumbnail.
      SiteConfig.default("cards", "post-link")&.[]("default_image")
    end

    # Format date (posts only)
    date_raw = "" unless is_post_record
    date = ""
    if date_raw.present?
      begin
        # Handle both Date objects and strings
        parsed_date = date_raw.is_a?(Date) ? date_raw : Date.parse(date_raw.to_s)
        date = parsed_date.strftime("%b %d, %Y")
      rescue
        date = date_raw.to_s  # Fallback to original if parsing fails
      end
    end

    # Build metadata line (author • date)
    metadata_parts = [ author, date ].reject(&:blank?)
    metadata = metadata_parts.join(" • ")

    # Products show their price in the metadata slot (author/date are blank for
    # non-post records). One concrete product → one real price.
    price = if referenced_post.is_a?(Product) && referenced_post.price.present?
      "#{get_currency_symbol}#{format('%.2f', referenced_post.price)}"
    else
      ""
    end

    # A product's variant (e.g. Vinyl, Ebook) shows next to the title; blank
    # for posts and for products without a variant.
    variant = referenced_post.is_a?(Product) ? referenced_post.variant.to_s : ""

    # Excerpt resolution + truncation. Shared resolver so any post-link
    # size can use it — large passes 200, medium would pass 120 if/when
    # its partial starts rendering excerpts. The resolver handles the
    # three-tier fallback (explicit > post metadata excerpt > post's
    # first prose paragraph) and the truncation cap.
    card_excerpt = resolve_card_excerpt(
      explicit:        excerpt,
      referenced_post: referenced_post,
      max_length:      300,
    )

    # Build HTML based on style
    if style == "large"
      ApplicationController.renderer.render(
        partial: "cards/post_link_large",
        locals: {
          kind:      kind,
          variant:   variant,
          title:     title,
          url:       url,
          image:     image,
          metadata:  metadata,
          price:     price,
          subtitle:  subtitle,
          excerpt:   card_excerpt,
          show_excerpt: show_excerpt,
          link_text: link_text,
          author:    author,
          date:      date
        },
      )
    elsif style == "medium"
      # Medium style: image, title, metadata, excerpt, link (smaller than large)
      ApplicationController.renderer.render(
        partial: "cards/post_link_medium",
        locals: {
          kind:      kind,
          variant:   variant,
          title:     title,
          subtitle: subtitle,
          url:       url,
          image:     image,
          metadata:  metadata,
          price:     price,
          excerpt:   card_excerpt,
          show_excerpt: show_excerpt,
          link_text: link_text,
          author:    author,
          date:      date
        },
      )
    else
      # Small style: image, title, subtitle, metadata, link (no excerpt)
      ApplicationController.renderer.render(
        partial: "cards/post_link_small",
        locals: {
          kind:      kind,
          variant:   variant,
          title:     title,
          subtitle:  subtitle,
          url:       url,
          image:     image,
          metadata:  metadata,
          price:     price,
          excerpt:   card_excerpt,
          show_excerpt: show_excerpt,
          link_text: link_text,
          author:    author,
          date:      date
        },
      )
    end
  end

  # Resolve and truncate a card excerpt with the full fallback chain:
  #   1. `explicit` — card-level or post-metadata excerpt (already
  #      merged together by render_post_link before this is called)
  #   2. first prose paragraph of the referenced post (skipping
  #      fenced blocks, headings, lists, blockquotes, HTML)
  # Returns "" when neither source produces text. Centralized here so
  # the same fallback semantics + truncation apply to every post-link
  # size — large passes max_length: 200 today; medium / small can pass
  # their own value when their partials start rendering excerpt.
  def resolve_card_excerpt(explicit:, referenced_post:, max_length:)
    text = explicit.to_s
    text = first_paragraph_of_post(referenced_post) if text.blank? && referenced_post.present?
    return "" if text.blank?
    text.length > max_length ? text[0..max_length - 3] + "..." : text
  end

  # Walk a post's markdown content line by line, looking for the first
  # chunk that reads as actual prose. Skips:
  #   * fenced blocks of any kind (```collection, ```card, ```ruby, …)
  #   * ATX headings (#, ##, …)
  #   * blockquote lines (>)
  #   * unordered + ordered list items (-, *, +, 1.)
  #   * HTML blocks (lines starting with <)
  #   * table rows (|...|...|)
  # Returns "" if no chunk qualifies. After picking the prose paragraph,
  # strips light markdown decoration so the result reads as plain text.
  #
  # Not a full markdown parser — line-based heuristic. Good enough for
  # a teaser, and crucially it doesn't dump a leading ```collection
  # block's YAML into the card the way a naive blank-line split would.
  def first_paragraph_of_post(post)
    return "" unless post && post.respond_to?(:content) && post.content.present?

    in_fence = false
    current = []
    paragraphs = []

    post.content.to_s.each_line do |line|
      if line.lstrip.start_with?("```")
        in_fence = !in_fence
        paragraphs << current.join unless current.empty?
        current = []
        next
      end

      next if in_fence

      if line.strip.empty?
        paragraphs << current.join unless current.empty?
        current = []
      else
        current << line
      end
    end
    paragraphs << current.join unless current.empty?

    prose = paragraphs.find do |p|
      stripped = p.strip
      next false if stripped.empty?
      next false if stripped.start_with?("#")           # heading
      next false if stripped.start_with?(">")           # blockquote
      next false if stripped.start_with?("<")           # HTML block
      next false if stripped =~ /\A[-*+]\s/             # unordered list
      next false if stripped =~ /\A\d+\.\s/             # ordered list
      next false if stripped =~ /\A\|.*\|/              # table row
      true
    end

    return "" if prose.blank?

    prose
      .strip
      .gsub(/!\[([^\]]*)\]\([^)]+\)/, "")          # ![alt](url) → "" (images)
      .gsub(/\[([^\]]+)\]\([^)]+\)/, '\1')         # [text](url) → text
      .gsub(/<\/?[^>]+>/, "")                      # strip inline HTML tags
      .gsub(/[*_`]/, "")                           # emphasis / inline code chars
      .strip
  end

  ### ASIDES

  def render_aside(config, preview: false)
    text = config[:text] || ""
    image = config[:image] || ""
    link = config[:link] || ""
    link_text = config[:link_text] || ""
    default_link_text = SiteConfig.default("cards", "aside")&.[]("default_link_text") || "→"

    # Build the content
    content = []
    content << "<img src=\"#{image}\" alt=\"\" class=\"aside-image\">" if image.present?

    # Collect text + link as a group so they can be wrapped in
    # `.aside-body`.
    body_parts = []

    if text.present?
      if link.present?
        if link_text.present?
          # Case 3: Link with custom link text - text separate from link
          body_parts << "<div class=\"aside-text\">#{text}</div>"
          body_parts << "<a href=\"#{link}\" class=\"aside-link\">#{link_text}</a>"
        else
          # Case 2: Link without link text - arrow inline with text
          body_parts << "<div class=\"aside-text\"><a href=\"#{link}\" class=\"aside-link-inline\">#{text} #{default_link_text}</a></div>"
        end
      else
        # Case 1: No link - just text
        body_parts << "<div class=\"aside-text\">#{text}</div>"
      end
    end

    content << "<div class=\"aside-body\">\n#{body_parts.join("\n")}\n</div>" if body_parts.any?

    # Determine if this is image-only
    aside_class = (image.present? && text.blank? && link_text.blank?) ? "card card-aside image-only" : "card card-aside"

    <<~HTML
      <div class="#{aside_class}">
        #{content.join("\n")}
      </div>
    HTML
  end

  # FORMS

  def process_forms(content, preview: false)
    replace_fenced_blocks(content, "form") do |yaml_content|
      begin
        form_config = YAML.safe_load(yaml_content)
        render_form(form_config)
      rescue => e
        Rails.logger.error "Form YAML parsing error: #{e.message}"
        dev_warning("Form YAML parse error", e.message, yaml_content.strip)
      end
    end
  end

  def render_form(config)
    form_type = roeanji_kind(config)
    button_text = config["button-text"] || config["button_text"] || default_button_text(form_type)

    result = case form_type
    when "paid_content"
      text = config["text"] || "This is premium content. Upgrade to continue reading."
      button_text = config["button-text"] || config["button_text"] || "Become a paid member"
      render_paid_content_form(text, button_text)
    when "signup"
      upgrade_text = config["upgrade-button-text"] || config["upgrade_button_text"]
      render_signup_form(button_text, upgrade_text)
    when "signin"
      render_signin_form(button_text)
    when "checkout"
      member_text = config["member-button-text"] || config["member_button_text"] || button_text
      non_member_text = config["non-member-button-text"] || config["non_member_button_text"]
      render_checkout_form(member_text, non_member_text)
    when "unsubscribe"  # ADD THIS
      render_unsubscribe_form(button_text)
    when "donate"
      render_donate_form(button_text)
    else
      dev_warning("Unknown form type", "'#{form_type}' is not a recognised form type.",
        "Valid types: signup, signin, checkout, donate, unsubscribe, paid_content")
    end

    roeanji_kind_conflict_warning(config) + result.to_s
  rescue => e
    Rails.logger.error "Form rendering error: #{e.message}"
    dev_warning("Form rendering error", e.message)
  end

  # ── Roe-anji "kind" selector (for / type) ─────────────────────────────
  #
  # Blocks that pick a variant select it with `for` (preferred for button/form
  # — reads as "a form FOR signup", "a button FOR share") or `type` (the
  # universal selector used elsewhere, e.g. cards). Both are accepted; `for`
  # wins when both are present. `default` is returned when neither is set
  # (buttons default to "product" — a bare button is a store button by design).

  def roeanji_kind(config, default: nil)
    config["for"].presence || config["type"].presence || default
  end

  # Dev-only warning when a block sets BOTH `for` and `type` to *different*
  # values (usually a typo). "" otherwise. `for` is the one that takes effect.
  def roeanji_kind_conflict_warning(config)
    f = config["for"].presence
    t = config["type"].presence
    return "" unless f && t && f != t

    dev_warning("Conflicting selector",
      "This block sets both `for: #{f}` and `type: #{t}` — `for` wins.",
      "They mean the same thing here; keep just one.")
  end

  def default_button_text(form_type)
    {
      "signup" => "Sign Up",
      "signin" => "Sign In",
      "checkout" => "Upgrade",
      "donate" => "Donate"
    }[form_type] || "Submit"
  end

  def render_donate_form(button_text)
    unless SiteFeature.donations_enabled?
      if Rails.env.development?
        reason = if !SiteFeature.payments_feature_enabled?
          "payments not enabled in members.yml"
        elsif !SiteFeature.payments_mode&.in?(%w[donations both])
          "payments.mode in members.yml must be 'donations' or 'both' (currently '#{SiteFeature.payments_mode}')"
        elsif !StripeConfig.current.keys_present?
          "Stripe keys not configured — add them in Admin → Settings → Integrations"
        else
          "donations not enabled"
        end
        return dev_warning("Donate form unavailable", reason)
      end
      return ""
    end

    currency = (StripeConfig.current.currency.presence || "usd").upcase

    # Buttons render with bare amounts; the donate-form Stimulus
    # controller hydrates them with localized currency labels on
    # connect. This avoids a flash of wrong-currency symbols on
    # non-USD sites.
    presets = SiteFeature.donation_amounts.map do |amt|
      <<~HTML.strip
        <button type="button"
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
        <button type="submit" class="btn-primary">#{button_text}</button>
      </form>
    HTML
  end

  def render_unsubscribe_form(button_text)
    # Token will be in URL, form will POST to same path
    <<~HTML
      <form action="" method="post">
        <input type="hidden" name="authenticity_token" value="#{form_authenticity_token}">
        <button type="submit" class="btn-destructive">#{button_text}</button>
      </form>
    HTML
  end

  def render_paid_content_form(text, button_text)
    # This will act as a content gate - everything after this is paid
    <<~HTML
      <!-- PAID_CONTENT_GATE -->
      <div class="paid-content-gate">
        <p>#{text}</p>
        <a href="/upgrade" class="btn-primary">#{button_text}</a>
      </div>
    HTML
  end

  def render_signup_form(button_text, upgrade_button_text = nil)
    # In static-site mode, render a link to the dynamic /sign-up page
    # instead of an embedded form. The embedded form would need a fresh
    # CSRF token at submission time, and a token baked in at static
    # build time would be stale. The link approach lets the user keep
    # ```form for: signup``` blocks in their content — dynamic mode
    # renders the real form, static mode renders a button-link that
    # routes the visitor to the dynamic Rails-served signup page where
    # CSRF works correctly.
    if @rendering_static
      return <<~HTML
        <div class="signup-link-block">
          <a href="/sign-up" class="btn-primary">#{CGI.escape_html(button_text)}</a>
        </div>
      HTML
    end

    # Check if payments are actually enabled
    payments_enabled = SiteConfig.feature("members", "payments.enabled")
    payments_enabled = (payments_enabled == true || payments_enabled == "true")

    # Only show upgrade button if payments are enabled AND text is provided
    upgrade_button = if upgrade_button_text.present? && payments_enabled
      <<~HTML
        <button type="submit" formaction="/signup_and_checkout" class="btn-primary">#{upgrade_button_text}</button>
      HTML
    else
      ""
    end

    # Check if there's a member with errors (from failed submission)
    # Access member from render context if available
    member = @render_context&.dig(:member)
    error_html = ""
    if member && member.errors.any?
      error_messages = member.errors.full_messages.map { |msg| "<li>#{CGI.escape_html(msg)}</li>" }.join
      error_html = <<~HTML
        <div class="form-errors">
          <h3>Errors:</h3>
          <ul>
            #{error_messages}
          </ul>
        </div>
      HTML
    end

    # Get values from failed submission if present
    name_value = member ? CGI.escape_html(member.name.to_s) : ""
    email_value = member ? CGI.escape_html(member.email.to_s) : ""

    <<~HTML
      <form action="/signup" method="post">
        <input type="hidden" name="authenticity_token" value="#{form_authenticity_token}">

        #{error_html}

        <div class="form-field">
          <label for="member_name">Name</label>
          <input type="text" name="member[name]" id="member_name" value="#{name_value}" required>
        </div>

        <div class="form-field">
          <label for="member_email">Email</label>
          <input type="email" name="member[email]" id="member_email" value="#{email_value}" required>
        </div>

        <button type="submit" class="btn-outline">#{button_text}</button>
        #{upgrade_button}
      </form>
    HTML
  end

  def render_signin_form(button_text = "Send Magic Link")
    # Same static-mode fallback as render_signup_form — link to the
    # dynamic /sign-in page, where the CSRF token will be fresh at
    # submission time.
    if @rendering_static
      return <<~HTML
        <div class="signin-link-block">
          <a href="/sign-in" class="btn-primary">#{CGI.escape_html(button_text)}</a>
        </div>
      HTML
    end

    <<~HTML
      <form action="/signin" method="post">
        <input type="hidden" name="authenticity_token" value="#{form_authenticity_token}">

        <div class="form-field">
          <label for="member_email">Email</label>
          <input type="email" name="member[email]" id="member_email" required>
        </div>

        <button type="submit" class="btn-outline">#{button_text}</button>
      </form>
    HTML
  end

  def render_checkout_form(member_button_text, non_member_button_text = nil)
    if non_member_button_text.blank?
      return <<~HTML
        <form action="/checkout" method="post" class="checkout-form" data-turbo="false">
          <input type="hidden" name="authenticity_token" value="#{form_authenticity_token}">
          <button type="submit" class="btn-primary">#{member_button_text}</button>
        </form>
      HTML
    end

    <<~HTML
      <div class="checkout-form-wrapper MEMBER_STATUS_PLACEHOLDER">
        <form action="/checkout" method="post" class="checkout-form member-checkout" data-turbo="false">
          <input type="hidden" name="authenticity_token" value="#{form_authenticity_token}">
          <button type="submit" class="btn-primary">#{member_button_text}</button>
        </form>

        <div class="non-member-checkout">
          <a href="/sign-up" class="btn-primary" data-turbo="false">#{non_member_button_text}</a>
        </div>
      </div>
    HTML
  end

  def form_authenticity_token
    # You might need to pass this in from the view context
    # For now, return a placeholder that will be replaced in the view
    "AUTHENTICITY_TOKEN_PLACEHOLDER"
  end

  # Finds a linkable content record by slug or path. Checks posts first
  # (most common), then pages, products, and user documentation.
  # Roe's own docs (file_path contains /roe/) are excluded — those are
  # system docs and not intended as link targets in content.
  def find_post_by_slug(slug_or_path)
    raw = slug_or_path.to_s.strip

    # Strip known prefixes to get the bare slug
    slug = raw
      .sub(%r{^/posts/}, "")
      .sub(%r{^/pages/}, "")
      .sub(%r{^/store/}, "")
      .sub(%r{^/documentation/}, "")
      .sub(%r{^/}, "")

    Post.where("json_extract(metadata, '$.url_name') = ?", slug).first ||
      Page.where("json_extract(metadata, '$.url_name') = ?", slug).first ||
      Product.where("json_extract(metadata, '$.url_name') = ?", slug).first ||
      Documentation.where("json_extract(metadata, '$.url_name') = ?", slug)
                   .where("file_path NOT LIKE '%/roe/%'").first
  end

  def render_error_card(message)
    <<~HTML
      <div class="card is-error">
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
          kind: roeanji_kind(config, default: "product"),
          conflict: roeanji_kind_conflict_warning(config),
          start_pos: start_pos,
          end_pos: end_pos,
          match: $~
        }
      rescue => e
        Rails.logger.error "Button parsing error: #{e.message}"
        # Replace the failed button block with a dev warning
        if Rails.env.development?
          buttons << {
            config: {},
            kind: "product",
            conflict: "",
            start_pos: start_pos,
            end_pos: end_pos,
            error: e.message,
            raw: config_text.strip
          }
        end
      end
    end

    return content if buttons.empty?

    # Group consecutive buttons (no blank lines between)
    groups = []
    current_group = [ buttons.first ]

    buttons.each_cons(2) do |prev, curr|
      # Check if there's a blank line between these buttons
      text_between = content[prev[:end_pos]...curr[:start_pos]]

      # Only PRODUCT buttons collapse into a SKU variant-list. A blank line
      # breaks a group as before; so does a non-product button (e.g. a
      # `for: share`) on either side — those always render on their own.
      if text_between =~ /\n\s*\n/ || prev[:kind] != "product" || curr[:kind] != "product"
        groups << current_group
        current_group = [ curr ]
      else
        # No blank line, both product - same group
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

      # Check if any button in the group has a parse error
      if group.any? { |b| b[:error] }
        rendered = group.map do |btn|
          if btn[:error]
            dev_warning("Button parse error", btn[:error], btn[:raw])
          else
            ProductButtonRenderer.render(btn[:config], context)
          end
        end.join("\n")
      elsif group.first[:kind] != "product"
        # Non-product button. Grouping guarantees this is a singleton, so
        # dispatch it by its for/type kind (product is the default path below).
        rendered = render_action_button(group.first, context)
      elsif group.length > 1
        # Multiple consecutive buttons - render as variant list
        skus = group.map { |b| b[:config]["sku"] }.compact
        if skus.length > 1
          renderer = ProductButtonRenderer.new({ "skus" => skus }, context)
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

      # Surface any for/type conflict warnings for the buttons in this group.
      rendered = group.filter_map { |b| b[:conflict].presence }.join + rendered

      # Replace in result
      first_btn = group.first
      last_btn = group.last
      original_text = content[first_btn[:start_pos]...last_btn[:end_pos]]

      result.sub!(original_text, rendered)
    end

    result
  end

  # Dispatch a NON-product button by its `for`/`type` kind. Product buttons go
  # through ProductButtonRenderer (the default, handled inline in
  # process_buttons); this is where the other kinds live. Only the dispatch is
  # scaffolded for now — specific renderers (e.g. `share`) get added as `when`
  # branches. An unrecognised kind dev-warns rather than rendering nothing.
  def render_action_button(button, context)
    return render_share_button(button[:config], context)   if button[:kind] == "share"
    return render_members_button(button[:config], context) if button[:kind] == "subscribe"

    dev_warning("Unknown button type",
      "'#{button[:kind]}' is not a recognised button type.",
      "Valid: product (the default when no for/type is given), share, subscribe.")
  end

  # A "Subscribe" button that links to the members sign-up page (subscribing to
  # the newsletter is becoming a member). A plain button-link, not the inline
  # signup form. Feature-gated: no members feature, no sign-up page → dev-warn.
  # `label:` (default "Subscribe"), `url:` (default /sign-up), and `style:`
  # (→ `members-<token>` classes) are all overridable.
  def render_members_button(config, _context)
    unless SiteFeature.members_enabled?
      return dev_warning("Subscribe button unavailable",
        "Members aren't enabled, so there's no sign-up page to link to.",
        "Enable members in members.yml.")
    end

    label = ERB::Util.html_escape(config["label"].presence || "Subscribe")
    url   = ERB::Util.html_escape(config["url"].presence || "/sign-up")
    css   = ([ "btn-primary" ] + action_button_style_classes(config, "members")).join(" ")

    %(<a class="#{css}" href="#{url}">#{label}</a>)
  end

  # A share button. Native share sheet where supported (mobile), Copy link +
  # Email everywhere else — see share_controller.js. URL/title/text are read
  # client-side from the page's canonical link + og:title so they match what
  # unfurls on social; `url:`, `title:`, `text:`, `label:` config override them.
  # Map a Roe-anji `style:` value (one or more space-separated tokens) to
  # sanitised modifier classes, e.g. on a share button `style: small center` →
  # "share-small share-center". Lets the theme restyle action buttons (size,
  # alignment, …) without a new config key each time — the same `style` pattern
  # the rest of Roe-anji uses.
  def action_button_style_classes(config, prefix)
    config["style"].to_s.split.filter_map do |token|
      slug = token.downcase.gsub(/[^a-z0-9\-]/, "")
      "#{prefix}-#{slug}" if slug.present?
    end
  end

  def render_share_button(config, _context)
    label = ERB::Util.html_escape(config["label"].presence || "Share")
    url   = ERB::Util.html_escape(config["url"].to_s)
    title = ERB::Util.html_escape(config["title"].to_s)
    text  = ERB::Util.html_escape(config["text"].to_s)
    # Only the opt-in `style:` modifier classes — no default hook classes, so a
    # future cleanup can't break themes that relied on them. Style the buttons
    # via btn-primary/btn-outline or a `style:` value.
    styles     = action_button_style_classes(config, "share")
    class_attr = styles.any? ? %( class="#{styles.join(' ')}") : ""

    # Only emit the value attrs that were actually set; a blank one is just the
    # controller's default (read the canonical URL + og:title off the page).
    data = { "url" => url, "title" => title, "text" => text }
      .filter_map { |k, v| %(data-share-#{k}-value="#{v}") if v.present? }
      .join(" ")
    data = " #{data}" unless data.empty?

    # Progressive enhancement: the trigger is `hidden` and the menu is visible
    # by default, so with no JS the reader still sees Copy link + Email (Email
    # works with no JS). On connect the controller flips that — reveals the
    # trigger, collapses the menu — so with JS it's a single Share button that
    # opens the menu on desktop / the native sheet on touch. The menu carries
    # `.button-menu`, the shared hook for any button→menu action (share,
    # subscribe…) so the theme can size those options once.
    <<~HTML.strip
      <div#{class_attr} data-controller="share"#{data}>
        <button type="button" class="btn-primary" data-share-target="trigger" data-action="share#toggle" aria-haspopup="true" aria-expanded="false" hidden>#{label}</button>
        <div class="button-menu" data-share-target="menu">
          <button type="button" class="btn-outline" data-share-target="copy" data-action="share#copy">Copy link</button>
          <a class="btn-outline" data-share-target="email" href="mailto:">Email</a>
        </div>
        <span data-share-target="feedback" role="status" aria-live="polite"></span>
      </div>
    HTML
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

  # Renders an amber dev-only warning box.
  # Silent (returns "") in production so no debug info leaks.
  #
  #   dev_warning("Title", "What went wrong", "optional hint or context")
  #
  def dev_warning(title, message, hint = nil)
    return "" unless Rails.env.development?

    hint_html = hint ? "<br><span style='color:#78350f'>#{CGI.escapeHTML(hint.to_s)}</span>" : ""
    <<~HTML
      <div style="border:2px dashed #f59e0b;padding:0.75rem 1rem;font-family:monospace;font-size:0.8rem;color:#92400e;background:#fffbeb;margin:0.5rem 0;">
        <strong>⚠️ #{CGI.escapeHTML(title)}</strong><br>
        #{CGI.escapeHTML(message.to_s)}#{hint_html}
      </div>
    HTML
  end
end
