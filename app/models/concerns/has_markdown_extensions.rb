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

    # Whether this render is an editor preview. Same reasoning as the flag
    # above: dev_warning is reached from a dozen renderers and threading a
    # keyword through all of them to answer one question isn't worth it.
    # Defaults to false, so any caller that doesn't ask for warnings gets none.
    @rendering_preview = preview

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

    # Restore code blocks (now as HTML). See
    # docs/04-markdown-extensions.md#code-block-protection for why the
    # wrapping paragraph goes too, and why gsub takes a block.
    #
    # Take the wrapping paragraph with the token where there is one. Kramdown
    # wraps a bare placeholder in <p>, and <pre> can't live inside <p> — so
    # replacing only the token produces `<p><pre>…</pre></p>`, which the next
    # Nokogiri pass rewrites to `<p></p><pre>…</pre>`, leaving a stray empty
    # paragraph before every code block on the site. The bare-token pass after
    # it handles placements Kramdown doesn't wrap, e.g. inside a list item.
    #
    # Both use the BLOCK form of gsub on purpose: with a string replacement
    # Ruby reads \0, \1 and \\ in the replacement as backreferences, which
    # silently mangles any code block containing them.
    code_blocks.each do |token, html_code|
      html.gsub!(%r{<p>\s*#{Regexp.escape(token)}\s*</p>}) { html_code }
      html.gsub!(token) { html_code }
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

  # Written in the paragraph that follows a floated pullquote to choose where the
  # text wraps around it, instead of letting Roe pick a sentence near the middle.
  PULLQUOTE_SPLIT_MARKER = "||"

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

  # Fingerprint of the members every ```collection block in this record's body
  # currently resolves to. The static generator stores this in its manifest so
  # it can regenerate an aggregation page (e.g. the glossary) when a
  # collection's membership — or a shown member's content — changes, even
  # though this record's own updated_at didn't. Returns nil when the body
  # embeds no collections.
  #
  # Each block contributes its ordered, displayed members as
  # "Class:id:updated_at" tuples, so add/remove, reorder, and edits to a shown
  # member all move the digest. The block's own config (query, limit, order)
  # lives in this body, so a config change already bumps this record's
  # updated_at and needs no separate tracking here.
  def embedded_collection_fingerprint
    blocks = content.to_s.scan(/^ *```collection\r?\n(.*?)```/m).map(&:first)
    return nil if blocks.empty?

    parts = blocks.map do |config_text|
      items, = resolve_collection_items(parse_collection_config(config_text))
      Array(items).map { |i| "#{i.class.name}:#{i.id}:#{i.updated_at.to_i}" }.join(",")
    end
    Digest::SHA1.hexdigest(parts.join("|"))
  end

  private

  def render_code_block(code, language)
    # Drop the newline before the closing fence — plus any indentation the
    # fence carries when the block sits inside a list — so it doesn't render
    # as a trailing blank line inside the <pre>. (Poetry blocks do the same.)
    code = code.sub(/\n[ \t]*\z/, "")
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

  # Footnote quirks (empty trailing <p>, ids on <sup>, repeat references):
  # see docs/04-markdown-extensions.md#known-quirks
  def add_footnote_backlinks(html)
    doc = Nokogiri::HTML::DocumentFragment.parse(html)

    # Only the footnote list's OWN items, so a list inside a footnote doesn't
    # shift the numbering. The child combinator has to reach all the way up:
    # `.footnotes ol > li` still matches the items of a nested <ol>, because
    # that <ol> is itself a descendant of .footnotes — which numbered a
    # footnote containing an ordered list as several footnotes, and pushed
    # every note after it out of step. `<ul>` never triggered it, which is why
    # it looked fixed.
    footnotes = doc.css(".footnotes > ol > li")

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

      append_extra_returns(doc, li, footnote_id, number)
    end

    doc.to_html
  end

  # A footnote referenced more than once has only one place the leading number
  # can point, so on its own it always returns you to the first mention — even
  # if you arrived from the third.
  #
  # Kramdown ids repeat references `fnref:name`, `fnref:name:1`, `fnref:name:2`,
  # so every mention is addressable. When there's more than one, add a return
  # link per mention at the end of the note. That works with no JavaScript, and
  # doubles as a way to visit the other mentions.
  #
  # site_js/footnotes.js then enhances it: clicking a reference repoints this
  # note's leading number at that specific mention, so the number returns you
  # where you actually came from. Markup is untouched for single-reference
  # footnotes, which is nearly all of them.
  def append_extra_returns(doc, li, footnote_id, number)
    references = doc.css(%(a[href="##{footnote_id}"]))
    return if references.size < 2

    returns = Nokogiri::XML::Node.new("span", doc)
    returns["class"] = "footnote-returns"

    references.each_with_index do |ref, i|
      # Kramdown hangs the id on the wrapping <sup>, not the <a>:
      #   <sup id="fnref:reuse"><a href="#fn:reuse" class="footnote">1</a></sup>
      ref_id = ref["id"].presence || ref.parent&.[]("id")
      next if ref_id.blank?

      link = Nokogiri::XML::Node.new("a", doc)
      link["href"] = "##{ref_id}"
      link["class"] = "footnote-return"
      link["role"] = "doc-backlink"
      link["aria-label"] = "Return to mention #{i + 1} of reference #{number}"
      link.inner_html = %(<span aria-hidden="true">↩</span><sup>#{i + 1}</sup>)

      returns.add_child(link)
    end

    return if returns.element_children.empty?

    # Kramdown already makes a home for a backlink. With
    # footnote_backlinks_inline it appends to the note's last paragraph, and
    # when the note ends in a block (quote, list, code, table, image) it adds a
    # paragraph to hold it — which, since footnote_backlink is "", arrives
    # empty. Put the links in that paragraph either way: after the text where
    # there is text, and filling the empty slot otherwise. Appending to the <li>
    # instead would leave the phantom paragraph sitting between the block and
    # the links.
    last = li.element_children.last
    if last && last.name == "p"
      last.add_child(returns)
    else
      li.add_child(returns)
    end
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
  # A space before the caption is allowed, because the two other places that
  # read this syntax — the consecutive-image grouper and the gallery scanner —
  # both allow one, and a line that works inside a gallery should not stop
  # working when it's lifted out. Spaces and tabs only, never a newline: the
  # caption belongs to the image on its line, and `\s*` would let an emphasised
  # paragraph underneath be swallowed as one.
  #
  # Runs before Kramdown so the raw HTML block is passed through
  # unchanged. The image is rendered via ResponsiveImageRenderer so
  # it gets the same srcset/picture treatment as uncaptioned images.
  def process_image_captions(markdown)
    markdown.gsub(/!\[([^\]]*)\]\(([^)]+)\)[ \t]*\(\*([^*]+)\*\)/) do
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
  GALLERY_DIRECTIVES = GalleryBuilderSchema::DIRECTIVES

  def render_gallery(content, preview: false, index: 0)
    config, image_rows, strays = parse_gallery(content)
    return (preview ? "<!-- Empty gallery -->" : "") if image_rows.flatten.empty?

    notice = gallery_directive_warning(strays) + gallery_ratio_warning(config["aspect_ratio"])
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
    # zoom overlay's data-sizes="100vw" pulls the largest). The notice goes
    # outside that wrapper — it's already HTML, and "" when warnings are off.
    [ notice, "", "{::nomarkdown}", body, "{:/nomarkdown}", "" ].join("\n")
  end

  # A directive line the gallery threw away. `carousel:` is the one people
  # actually write, so it's named outright rather than left to spelling.
  def gallery_directive_warning(strays)
    return "" if strays.blank? || !show_block_warnings?

    named = strays.filter_map do |key|
      if (real = GalleryBuilderSchema::ALIASES[key])
        "`#{key}:` isn't a gallery directive — use `#{real}:`."
      elsif (near = nearest_term(key, GALLERY_DIRECTIVES))
        "`#{key}:` isn't a gallery directive — did you mean `#{near}:`?"
      end
    end
    return "" if named.empty?

    dev_warning("Gallery #{'option'.pluralize(named.size)} not understood", named.join(" "),
      "Unrecognized options are ignored.")
  end

  # Spell-checked, never restricted: a theme is free to define a
  # `gallery-ratio-<anything>` class, so only a near-miss of a known shape is
  # worth mentioning. An unknown value renders a class no stylesheet defines,
  # which does nothing at all and looks exactly like the default.
  def gallery_ratio_warning(value)
    return "" if value.blank? || !show_block_warnings?

    ratio = value.to_s.strip.downcase
    return "" if GalleryBuilderSchema::RATIOS.include?(ratio)

    near = nearest_term(ratio, GalleryBuilderSchema::RATIOS)
    return "" unless near

    dev_warning("Unknown aspect ratio",
      "Did you mean `#{near}`?",
      "Options: #{GalleryBuilderSchema::RATIOS.join(', ')}.")
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
  # Returns [config, image_rows, strays] — strays being `key: value` lines that
  # look like a directive but aren't one. The whitelist above means those aren't
  # merely ignored: they fall through to the image scanner, match nothing, and
  # are dropped with the row. Collected here so render_gallery can say so.
  def parse_gallery(content)
    config = {}
    image_lines = []
    strays = []

    content.to_s.each_line do |line|
      m = line.match(/\A\s*([a-z_]+)\s*:\s*(.+?)\s*\z/i)
      if m && line !~ /!\[/
        key = m[1].downcase
        if GALLERY_DIRECTIVES.include?(key)
          config[key] = m[2]
          next
        end
        strays << key
      end
      image_lines << line
    end

    rows = image_lines.join.split(/\n\s*\n/).map(&:strip).reject(&:empty?)
    image_rows = rows.map { |row| scan_gallery_images(row) }.reject(&:empty?)
    [ config, image_rows, strays ]
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
    value = SiteConfig.content("soft_line_breaks")
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
      # A misspelled key is silently dropped, so `limitt: 3` renders the whole
      # list with no hint that a limit was asked for. Prefixed, never
      # substituted: the collection itself is fine.
      unrecognised_option_warnings(config, "collection blocks") + render_collection(config)
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

  # Selection helpers (tag/podcast/category filters) now live in CollectionQuery,
  # shared with named feeds. This name-normalizer is still called elsewhere in
  # the renderer (menu curation), so it delegates rather than duplicating.
  def normalize_collection_names(value)
    CollectionQuery.normalize_names(value)
  end

  def render_collection(config)
    display_items, total_count, warning = resolve_collection_items(config)
    return warning if warning

    render_resolved_collection(config, display_items, total_count)
  end

  # Default source for a collection, shared by resolve_collection_items and
  # render_resolved_collection. Delegates to CollectionQuery so collections and
  # feeds resolve the source identically.
  def collection_source(config)
    CollectionQuery.source_for(config)
  end

  # What to call one item from a collection's source, so a warning about
  # documentation doesn't tell someone to add the tag to a post. `documentation`
  # has no singular worth using — "documentation article" is what a reader would
  # call it.
  def collection_source_noun(source)
    case source.to_s
    when "products" then "product"
    when "pages" then "page"
    when "documentation", %r{^documentation/} then "documentation article"
    else "post"
    end
  end

  # Resolve a limit/offset directive to an item count. Accepts a strict integer
  # ("11") or a percentage of the matched set ("50%", rounded to the nearest
  # item). Percentages let paired collections split a list into equal parts —
  # `limit: 50%` on one, `offset: 50%` on the next — without hardcoding counts
  # as the set grows. Both sides round identically, so the halves meet with no
  # gap or overlap. Blank/garbage → 0.
  def collection_count(value, total)
    str = value.to_s.strip
    if str.end_with?("%")
      (str.chomp("%").to_f / 100.0 * total).round
    else
      str.to_i
    end
  end

  # Parse a `limit: a-g` alphabetical range (or a single `limit: c`) into
  # [first, last] downcased letters, or nil when the value isn't a letter range.
  # Reversed ranges ("g-a") are tolerated.
  def parse_letter_range(value)
    m = value.to_s.strip.downcase.match(/\A([a-z])(?:\s*-\s*([a-z]))?\z/)
    return nil unless m
    a = m[1]
    b = m[2] || a
    a <= b ? [ a, b ] : [ b, a ]
  end

  # True when the item's title starts with a letter within [first, last].
  # Non-letter initials (numbers, symbols) fall outside every letter range.
  def title_initial_in_range?(item, range)
    initial = item.title.to_s.strip.downcase[0]
    return false unless initial
    initial.between?(range[0], range[1])
  end

  # Parse a `part: k/m` column directive into the Range of the ordered set that
  # column k of m occupies, or nil when it isn't a valid k/m (1 <= k <= m).
  # Boundaries are floored from the shared total, so the m slices partition the
  # set with no gaps or overlaps and sizes differing by at most one item.
  def parse_part(value, total)
    m = value.to_s.strip.match(%r{\A(\d+)\s*/\s*(\d+)\z})
    return nil unless m
    k, n = m[1].to_i, m[2].to_i
    return nil if n < 1 || k < 1 || k > n
    ((k - 1) * total / n)...(k * total / n)
  end

  # Resolve a parsed collection config to its final displayed members.
  # Returns [display_items, total_count, warning] — warning is dev-only HTML
  # that replaces the collection when the config is invalid (nil on the happy
  # path); total_count is the pre-offset/limit size (drives the "View all"
  # link). Shared by render_collection and embedded_collection_fingerprint so
  # change detection and rendering never disagree on membership.
  def resolve_collection_items(config)
    menu_template = config[:template].to_s.strip == "menu"
    source = collection_source(config)
    order_by = config[:order] || SiteConfig.default("collections", "default_order") || "date"
    # A menu is a menu, not a feed: with no explicit `order:` (usually a
    # url_name list), fall back to alphabetical rather than by date.
    order_by = "title" if config[:order].blank? && menu_template
    tags = config[:tags]

    # Get post_type from config or default, treating 'all' as nil (no filter)
    post_type = config[:post_type]
    post_type = nil if post_type == "all"

    # Validate tags in dev — warn about tags that don't exist on the source
    if show_block_warnings? && tags.present?
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
        source_name = collection_source_noun(source)
        return [ [], 0, dev_warning(
          "Unknown tag#{'s' if unknown.size > 1}",
          "#{unknown.map { |t| "'#{t}'" }.join(', ')} #{'does' if unknown.size == 1}#{'do' if unknown.size > 1} not exist on any #{source_name}.",
          "Existing tags: #{existing.any? ? existing.join(', ') : '(none yet)'}. " \
          "Add the tag to at least one #{source_name}'s metadata and it will show up in this collection."
        ) ]
      end
    end

    # Validate post_type in dev — catches typos like 'articles' instead of 'article'
    if show_block_warnings? && post_type.present? && source == "posts"
      valid_types = Post.post_type_options
      unless valid_types.include?(post_type)
        return [ [], 0, dev_warning(
          "Unknown post_type",
          "'#{post_type}' is not a recognised post type.",
          "Valid types: #{valid_types.join(', ')}"
        ) ]
      end
    end

    # Base selection (source + post_type/podcast/tags/category + `collection:`
    # membership) lives in CollectionQuery, shared with named feeds so the two
    # can never disagree about membership. The rendering-only steps below
    # (related, menus, ordering, limit/offset) stay here. A nil result means an
    # unknown source — warn in dev, render empty in prod, as before.
    items = CollectionQuery.new(config).records
    if items.nil?
      if show_block_warnings?
        valid = %w[posts pages documentation documentation/roe products]
        return [ [], 0, dev_warning("Unknown collection source",
          "'#{source}' is not a valid source.",
          "Valid sources: #{valid.join(', ')}") ]
      end
      items = []
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
    if menu_template
      # A menu's membership is the `order:` list unioned with anything tagged
      # `collection: <name>` — a page joins by being listed OR tagged. With
      # neither, there's nothing to show: bail with a notice (dev-only) rather
      # than silently dumping every page.
      has_list  = config[:order].present? && !sort_keyword?(config[:order])
      has_label = config[:collection].present?
      unless has_list || has_label
        return [ [], 0, dev_warning(
          "Empty menu collection",
          "This collection has template set to menu but has no order: list and no collection: name, so there's nothing to show.",
          "Add an order: list of url_names, or give it a collection: name and add the same collection: to the pages, posts, or products you want to show up here."
        ) ]
      end
      items = curate_menu(items, config[:order], config[:collection])
    elsif !related_filter || config[:order].present?
      items = apply_collection_order(items, order_by)
    end

    # Apply offset and limit
    limit_value = config[:limit]
    # A menu should list every matching item — a capped menu is a bug, not
    # a feature. Other templates keep the configured default limit.
    limit_value = "all" if limit_value.blank? && config[:template].to_s.strip == "menu"
    default_limit = SiteConfig.default("collections", "default_limit") || 10

    # Convert to array if needed
    items_array = items.is_a?(Array) ? items : items.to_a

    # limit: a-g — an alphabetical range on the title's first letter (also a
    # single letter, "limit: c"). It filters rather than counts, so it narrows
    # the set and shows all of it — splits a glossary into A–G / H–P sections.
    # Titles that don't start with a letter fall outside every letter range.
    if (letter_range = parse_letter_range(config[:limit]))
      items_array = items_array.select { |item| title_initial_in_range?(item, letter_range) }
      limit_value = "all"
    end

    total_count = items_array.count

    # k/m — an equal column slice of the matched set (column k of m), from
    # shared floored boundaries so the m columns never gap or overlap and differ
    # by at most one item. Written as `limit: 1/2` (it's just another way to say
    # what shows up) or the explicit `part: 1/2`; `part:` wins if both are set.
    # A slice fully determines what's shown, so offset and a numeric limit don't
    # apply. The "invalid" nudge fires only for an explicit `part:` — a non-k/m
    # `limit:` is a normal count/percentage/letter range, handled below.
    part_value = config[:part].presence || config[:limit]
    if (part_range = parse_part(part_value, total_count))
      return [ items_array[part_range] || [], total_count, nil ]
    elsif config[:part].present? && show_block_warnings?
      return [ [], 0, dev_warning(
        "Invalid part",
        "`part: #{config[:part]}` isn't a valid column slice. Use `k/m` with k from 1 to m (e.g. `part: 2/3`).",
        "For equal columns, give each block the same m: `1/3`, `2/3`, `3/3` — on `part:` or `limit:`."
      ) ]
    end

    # Apply offset (skip first N items). offset and limit each accept a strict
    # integer or a percentage of the matched set ("50%") — see collection_count.
    offset_value = collection_count(config[:offset], total_count)

    # A letter range belongs on `limit:` (it filters); on `offset:` it silently
    # parses to 0, so steer the author before they get a confusing result.
    if show_block_warnings? && config[:offset].present? && parse_letter_range(config[:offset])
      return [ [], 0, dev_warning(
        "Letter range on offset",
        "`offset: #{config[:offset]}` looks like a letter range, use `limit:` instead.",
        "(e.g. `limit: a-m` then `limit: n-z`)."
      ) ]
    end

    items_array = items_array[offset_value..-1] || [] if offset_value > 0

    # Offset skipped past everything: the collection has content, but `offset`
    # is at least as large as the item count, so nothing is left to show. Flag
    # it locally (prod still renders the empty collection as before) so the
    # author can spot a too-large offset instead of staring at a blank block.
    if show_block_warnings? && offset_value > 0 && total_count > 0 && items_array.empty?
      max_offset = total_count - 1
      hint = if max_offset < 1
        "Remove `offset` — this collection has only #{total_count} #{'item'.pluralize(total_count)}."
      else
        "Either remove `offset` altogether, or reduce it to `offset: #{max_offset}` or lower to see content."
      end
      return [ [], 0, dev_warning(
        "Collection offset skips all content",
        "This collection uses `offset: #{offset_value}` but has only #{total_count} #{'item'.pluralize(total_count)}, so there's nothing left to show here.",
        hint
      ) ]
    end

    if limit_value.to_s.downcase == "all"
      display_items = items_array
    elsif limit_value
      display_items = items_array.take(collection_count(limit_value, total_count))
    elsif offset_value > 0
      # A bare offset with no limit slices off a remainder — show all of it,
      # not the default page cap (which is meant for uncapped feeds). This is
      # what lets `limit: 50%` / `offset: 50%` two-column splits balance and
      # cover every item.
      display_items = items_array
    else
      display_items = items_array.take(default_limit)
    end

    [ display_items, total_count, nil ]
  end

  def render_resolved_collection(config, display_items, total_count)
    heading = config[:heading]
    source  = collection_source(config)
    show_more = config[:show_more] == "true" || config[:show_more] == true

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

    if template == "compact" || template == "glossary" || template == "menu" || template == "player" || template == "playlist"
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

    output.join("\n")
  end

  # Ordering lives in CollectionQuery, shared with feeds. These thin wrappers
  # keep the call sites in resolve_collection_items and curate_menu unchanged.
  def apply_collection_order(items, order_by)
    CollectionQuery.order_items(items, order_by)
  end

  def sort_keyword?(value)
    CollectionQuery.sort_keyword?(value)
  end

  # A menu's membership: its `order:` url_name list (those items, in that order)
  # unioned with anything tagged `collection: <name>` — a page joins by being
  # listed OR by carrying that collection name. Listed items lead, in list
  # order; tagged-but-unlisted items follow, alphabetically. Unresolved
  # url_names are skipped (logged in development so a typo is easy to spot).
  # Reached only when at least one of order/collection is present — an empty
  # menu is caught earlier with a notice.
  def curate_menu(items, order_list, label)
    all      = items.to_a
    has_list = order_list.present? && !sort_keyword?(order_list)

    listed = []
    if has_list
      wanted   = order_list.to_s.split(",").map { |s| s.strip.downcase }.reject(&:empty?)
      by_slug  = all.index_by { |item| item.url_name.to_s.downcase }
      resolved = wanted.map { |slug| by_slug[slug] }

      if Rails.env.development?
        missing = wanted.zip(resolved).reject { |_, item| item }.map(&:first)
        Rails.logger.warn("[Collection menu] order: url_names not found: #{missing.join(', ')}") if missing.any?
      end

      listed = resolved.compact
    end

    tagged = []
    if label.present?
      wanted_names = normalize_collection_names(label)
      listed_slugs = listed.map { |item| item.url_name.to_s.downcase }
      tagged = all.select { |item| item.respond_to?(:collection_names) && (item.collection_names & wanted_names).any? }
                  .reject { |item| listed_slugs.include?(item.url_name.to_s.downcase) }
                  .sort_by { |item| item.title.to_s.downcase }
    end

    listed + tagged
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
    when "menu"
      render_menu(items, config)
    when "player", "playlist"
      # `player` is now a card (the transport); as a collection template it's an
      # alias for `playlist` (the list). The transport comes from a `player` card.
      render_playlist(items, config)
    when "full"
      render_full(items, config)
    when "list"
      render_list(items, config)
    else
      render_list(items, config)
    end
  end

  def render_list(items, config = {})
    show_author   = collection_truthy?(config[:show_author])
    show_subtitle = collection_truthy?(config[:show_subtitle], default: true)
    show_date     = collection_truthy?(config[:show_date], default: true)

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
      if show_subtitle && item.respond_to?(:subtitle) && item.subtitle.present?
        output << "#{item.subtitle}"
        output << "{: .item-subtitle}"
        output << ""
      end

      # Meta row: date, optionally with " • author" appended
      date_str = show_date ? item_date(item) : nil
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

  # Image-on-the-right template. Includes everything from `list`, plus an
  # excerpt and a featured image. Like every content template, author is off
  # by default; pass `show_author: true` to add it. Subtitle, excerpt, and date
  # default on and can each be turned off. The image shows whenever the item
  # has one (no toggle).
  #
  # Media indicators (play / headphones for video / audio / podcast posts)
  # are added next to the title by decorate_title — same as every other
  # collection template. No icon overlay on the image.
  def render_full(items, config = {})
    show_author   = collection_truthy?(config[:show_author])
    show_subtitle = collection_truthy?(config[:show_subtitle], default: true)
    show_excerpt  = collection_truthy?(config[:show_excerpt], default: true)
    show_date     = collection_truthy?(config[:show_date], default: true)

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

      if show_subtitle && item.respond_to?(:subtitle) && item.subtitle.present?
        output << "#{item.subtitle}"
        output << "{: .item-subtitle}"
        output << ""
      end

      if show_excerpt && item.respond_to?(:excerpt) && item.excerpt.present?
        output << item.excerpt.to_s
        output << "{: .item-excerpt}"
        output << ""
      end

      date_str = show_date ? item_date(item) : nil
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

  # `menu` template: a bare list of links, nothing else — built for placement
  # areas like nav, footer, or a sidebar. `style: horizontal|vertical` sets a
  # modifier class (default vertical). Emits raw HTML (the wrapper carries no
  # markdown="1"), so Kramdown leaves the list intact; on the navigation file
  # the active-link pass still tags the current page.
  def render_menu(items, config)
    style = config[:style].to_s.strip.downcase
    style = "vertical" unless %w[horizontal vertical].include?(style)

    lis = items.map do |item|
      title = ERB::Util.html_escape(item.title.presence || "Untitled")
      %Q(  <li class="collection-menu-item"><a href="#{item_path(item)}">#{title}</a></li>)
    end.join("\n")

    list = %Q(<ul class="collection-menu collection-menu-#{style}">\n#{lis}\n</ul>)

    # In a layout file (header/footer/sidebar) a menu IS site navigation — wrap
    # it in a <nav> landmark. In a page body it's a content list, so leave the
    # bare <ul>. Label the landmark with the collection's (invisible) name when
    # set, so multiple navs stay distinguishable for assistive tech.
    return list unless is_a?(LayoutMarkdown)

    name = config[:collection].to_s.split(",").first.to_s.strip
    aria = name.present? ? %Q( aria-label="#{ERB::Util.html_escape(name)}") : ""
    %Q(<nav class="collection-nav"#{aria}>\n#{list}\n</nav>)
  end

  # A single-player playlist over a collection of audio posts — music tracks or
  # podcast episodes. The template emits every element and its DOM order; the
  # theme's CSS controls the entire look (symbols, layout, type). Structure:
  # header (cover/title/artist) ▸ now-playing ▸ transport (toggle/times/playhead)
  # ▸ the track list. Each row also carries a native <audio controls> as the
  # no-JS fallback; player.js hides those (adds .is-enhanced) and drives one
  # active track through the transport, auto-advancing on end.
  # The track/episode list on its own — `template: playlist`. Each row is a
  # native <audio controls> (no-JS fallback) plus data attributes (title, image,
  # url; audio via the <audio> src) so a `player` can adopt it as its queue.
  # This is the list half of the old combined player; the transport is the
  # `player` card.
  def render_playlist(items, config)
    tracks = items.select do |item|
      item.respond_to?(:audio) && item.audio.to_s.strip.present?
    end

    rows = tracks.each_with_index.map do |item, i|
      # Whether this track's AUDIO is protected, which is what decides if it
      # plays — not the post's own audience. An episode on a paid show inherits
      # protection with a blank audience of its own, and a row that looks free
      # but 403s reads as a broken player.
      paid   = playlist_track_paid?(item)
      title  = ERB::Util.html_escape(item.title.presence || "Untitled")
      number = ERB::Util.html_escape(player_track_number(item).presence || (i + 1).to_s)
      audio  = ERB::Util.html_escape(item.audio.to_s.strip)
      image  = ERB::Util.html_escape(player_item_image(item))
      url    = ERB::Util.html_escape(item_path(item))
      dur    = item.respond_to?(:duration) ? item.duration.to_s.strip : ""
      dur_html = dur.present? ? %Q(<span class="player-track-duration">#{ERB::Util.html_escape(dur)}</span>) : ""

      lock = paid ? paid_lock_icon : ""

      <<~HTML
        <li class="player-track#{paid ? ' is-paid' : ''}" data-player-track data-paid="#{paid}" data-title="#{title}" data-image="#{image}" data-url="#{url}">
          <div class="player-track-meta" data-player-select>
            <span class="player-track-number">#{number}</span>
            <span class="player-track-title">#{title}#{lock}</span>
            <a class="player-track-link" href="#{url}" target="_blank" rel="noopener" aria-label="Open #{title}"></a>
            #{dur_html}
          </div>
          <audio class="player-track-audio" controls preload="none" src="#{audio}"></audio>
        </li>
      HTML
    end.join

    %Q(<ol class="player-tracks" data-playlist>\n#{rows}</ol>)
  end

  # The release/podcast cover for the player — the artwork fallback when a track
  # has no image of its own. The association key comes from the block first, then
  # the current post/page (which usually carries it), so the artwork "just works"
  # on a podcast/release page. Empty when unscoped.
  def player_cover(config)
    release_key = config[:release].presence || player_context_key("release")
    podcast_key = config[:podcast].presence || player_context_key("podcast")
    raw =
      if release_key.present?
        ReleaseConfig.get(release_key).to_h["cover"]
      elsif podcast_key.present?
        PodcastConfig.get(podcast_key).to_h["artwork"]
      end
    resolve_player_image(raw)
  end

  # A post's own artwork (podcast episode / track image), if set.
  def player_item_image(item)
    return "" unless item.respond_to?(:metadata)
    resolve_player_image(item.metadata["image"])
  end

  # Config/metadata image references may be a bare filename (served from
  # /system/images/<name>), an absolute path, or a full URL. Normalize all three
  # — mirrors ApplicationHelper#config_image_path (kept in sync), but callable
  # from the model without a view context / route helpers.
  def resolve_player_image(value)
    v = value.to_s.strip
    return "" if v.empty? || v == "none"
    return v if v.start_with?("http://", "https://", "/")
    "/system/images/#{v}"
  end

  # A key from the current post/page metadata (self) when this markdown renders
  # in a content context; nil in a layout or when the key is absent.
  def player_context_key(key)
    return nil unless respond_to?(:metadata) && metadata.is_a?(Hash)
    metadata[key].to_s.strip.presence
  end

  # Artwork for the player card: explicit `image:` → the current post's own
  # image → the release/podcast cover (association-resolved). Empty for none.
  def player_card_artwork(config)
    explicit = resolve_player_image(config[:image])
    return explicit if explicit.present?
    own = respond_to?(:metadata) ? resolve_player_image(metadata["image"]) : ""
    return own if own.present?
    player_cover(config)
  end

  # `card` with `type: player` — the transport. Plays an explicit `audio:` (or a
  # bare `video:`), else the current post's audio/video. Reuses the audio-player
  # Stimulus controller and the .collection-player TUI base. The list is a
  # separate `playlist` collection; a later step lets this adopt one.
  def render_player_card(config, preview: false)
    audio_src = config[:audio].presence || (respond_to?(:audio) ? audio.to_s.strip.presence : nil)
    video_src = config[:video].presence || (respond_to?(:video) ? video.to_s.strip.presence : nil)

    if audio_src.blank? && video_src.present?
      # Minimal native video for now; the full video transport is a follow-up.
      return %Q(<div class="card-player card-player-video"><video class="player-video" controls preload="metadata" src="#{ERB::Util.html_escape(video_src)}"></video></div>)
    end

    card_title  = config[:title].presence || (respond_to?(:title) ? title.to_s : "")
    title_html  = ERB::Util.html_escape(card_title)
    info_url    = ERB::Util.html_escape(respond_to?(:url_name) ? item_path(self) : "#")

    # Own audio → <source> tags. With none, the transport still renders empty so
    # it can adopt a `playlist` on the page (the JS loads the first track).
    sources_html =
      if audio_src.present?
        s = ERB::Util.html_escape(audio_src)
        %Q(<source src="#{s}" type="audio/mpeg"><source src="#{s}" type="audio/mp4"><source src="#{s}" type="audio/ogg">)
      else
        ""
      end

    show_artwork = config[:show_artwork].to_s.strip.downcase != "false"
    cover        = player_cover(config)
    art          = show_artwork ? player_card_artwork(config) : ""
    figure_html  =
      if show_artwork
        img = art.present? ?
          %Q(<img class="player-cover" data-audio-player-target="artwork" src="#{ERB::Util.html_escape(art)}" alt="">) :
          %Q(<img class="player-cover" data-audio-player-target="artwork" alt="" hidden>)
        %Q(<figure class="player-figure">#{img}</figure>)
      else
        ""
      end

    <<~HTML
      <div class="card-player" data-controller="audio-player" data-audio-player-type-value="audio"#{member_upgrade_value} data-cover="#{ERB::Util.html_escape(cover)}">
        <audio data-audio-player-target="audio" preload="metadata" hidden>#{sources_html}</audio>
        <div class="player-body">
          #{figure_html}
          <div class="player-main">
            <div class="player-now">
              <span class="player-now-title" data-audio-player-target="title">#{title_html}</span>
              <a class="player-now-link" data-player-info href="#{info_url}" target="_blank" rel="noopener">[info]</a>
            </div>
            <div class="player-transport">
              <button type="button" class="player-toggle" data-audio-player-target="playButton" data-action="click->audio-player#togglePlay" data-playing="false" aria-label="Play"></button>
              <span class="player-time player-time-current" data-audio-player-target="currentTime">0:00</span>
              <div class="player-progress" data-audio-player-target="progressBar" data-action="mousedown->audio-player#startScrub touchstart->audio-player#startScrub" role="slider" aria-label="Seek" tabindex="0">
                <div class="player-progress-fill" data-audio-player-target="progressFill"></div>
                <div class="player-progress-handle" data-audio-player-target="progressHandle"></div>
              </div>
              <span class="player-time player-time-duration" data-audio-player-target="duration">0:00</span>
              <button type="button" class="player-speed" data-audio-player-target="speedButton" data-action="click->audio-player#cycleSpeed" aria-label="Playback speed">1×</button>
            </div>
          </div>
        </div>
      </div>
    HTML
  end

  # A track/episode's number for the player row: track_number, then
  # episode_number, else blank.
  def player_track_number(item)
    return "" unless item.respond_to?(:metadata)
    (item.metadata["track_number"].presence || item.metadata["episode_number"].presence).to_s
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

      if broken_image && show_block_warnings?
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

        # Grouped products can't be added to the cart from the grid — the buyer
        # picks a variant on the product page — so ALWAYS link there. The
        # configured button_text overrides the default label.
        label = grouped_button_text || "View"
        primary_for_link = find_primary_product(group_products) || display_product
        output << %Q(      <a href="#{item_path(primary_for_link)}" class="btn-primary btn-grid">#{label}</a>)
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

          # Same source as the product page's button and the `button` block —
          # see Product#snipcart_attributes. Building the list here by hand is
          # what let a grid button and a page button disagree.
          #
          # A digital product that can't deliver gets no button here either,
          # or a grid would remain a way to buy something the product page
          # already refuses to sell.
          if display_product.respond_to?(:deliverable?) && !display_product.deliverable?
            output << %Q(      <span class="btn-grid is-unavailable">Not available</span>)
            next
          end

          output << %Q(      <button class="snipcart-add-item btn-primary btn-grid")
          output << %Q(              data-turbo="false")
          display_product.snipcart_attributes(url: validation_url).each do |key, value|
            output << %Q(              #{key}="#{ERB::Util.html_escape(value)}")
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
      item.public_url
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

  # A playlist row is marked paid when its audio won't serve to the public.
  # That's the resolved media audience — a track can be protected by its show
  # or release without saying so itself — rather than show_paid_indicator?,
  # which asks whether the POST is paid.
  # Where to send someone who hits the player's paywall. Blank when the site
  # has no upgrade page — the notice then says what happened without linking
  # somewhere that doesn't exist.
  def member_upgrade_value
    return "" if @rendering_static

    page = member_upgrade_page
    return "" unless page&.url_name.present?

    %( data-audio-player-upgrade-url-value="/#{ERB::Util.html_escape(page.url_name)}")
  end

  def member_upgrade_page
    pages = Pathname.new(File.join(RoeSitePaths::SITE_PATH, "pages"))
    [ pages.join("members", "upgrade.md"), pages.join("upgrade.md") ]
      .filter_map { |path| Page.find_by(file_path: path.to_s) }
      .first
  rescue StandardError
    nil
  end

  def playlist_track_paid?(item)
    return false if @rendering_static
    return false unless SiteConfig.feature_enabled?("members")
    return false unless item.respond_to?(:media_audience)

    item.media_audience == "paid"
  end

  def show_paid_indicator?(item)
    # Suppress the paid lock in static-site builds — without a member
    # session there's no upgrade flow to drive viewers toward, so the
    # icon is just visual noise.
    return false if @rendering_static
    return false unless item.respond_to?(:audience) && item.audience == "paid"
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

  # An option line: a lowercase identifier, a colon, and the rest of the line.
  # Lowercase on purpose — prose that opens with "Note: …" is a sentence, not an
  # option, and capitalising is how people write it.
  CARD_OPTION_RE = /\A[ \t]*([a-z_][a-z0-9_]*)[ \t]*:[ \t]?(.*)\z/

  # Keys whose value runs on until the next option or the end of the block.
  # Prose, in other words. Everything else is a single value on its own line,
  # where a stray line underneath is far more likely to be a mistake than a
  # continuation — a second line under `image:` would just break the path.
  CARD_PROSE_KEYS = %w[text].freeze

  # Cards are `key: value` lines, except that a prose value carries on over
  # blank lines and all until the next option. That's what lets an aside hold
  # more than one paragraph.
  #
  # Unrecognised keys are still parsed as keys rather than swallowed into the
  # text above them, or a misspelled `postion:` would silently become part of
  # the card's prose instead of being reported.
  def parse_card_config(text)
    config = {}
    current = nil

    text.to_s.split("\n").each do |line|
      if (option = line.match(CARD_OPTION_RE))
        current = option[1]
        config[current.to_sym] = option[2].to_s
      elsif current && CARD_PROSE_KEYS.include?(current)
        config[current.to_sym] = "#{config[current.to_sym]}\n#{line}"
      end
    end

    config.transform_values(&:strip)
  end

  def render_card(config, preview: false)
    type = config[:type] || "pullquote"

    # Prefixed rather than substituted, and "" whenever warnings are off, so a
    # published page renders exactly what it rendered before. A card with a
    # misspelled option still draws — it just draws without that option, which
    # is the whole reason the mistake is so easy to miss.
    notice = card_warnings(type, config)

    body = case type
    when "pullquote"
      render_pullquote(config)
    when "aside"
      render_aside(config, preview: preview)
    when "post-link"
      render_post_link(config, preview: preview)
    when "product-link"
      render_product_link(config, preview: preview)
    when "player"
      render_player_card(config, preview: preview)
    else
      preview ? "<!-- Unknown card type -->" : ""
    end

    notice + body
  end

  # Why a card didn't come out the way it was written. An unknown type renders
  # nothing at all and a dropped option renders the default, both without a word
  # of explanation — the failures worth catching are the quiet ones.
  def card_warnings(type, config)
    return "" unless show_block_warnings?

    valid_types = CardBuilderSchema::TYPES.map { |t| t[:value] }
    unless valid_types.include?(type)
      return dev_warning(
        "Unknown card type",
        "'#{type}' is not a card type.#{did_you_mean(type, valid_types)}",
        "Valid types: #{valid_types.join(', ')}"
      )
    end

    [ missing_card_fields_warning(type, config),
      unrecognised_option_warnings(config, "#{type} cards") ].join
  end

  def missing_card_fields_warning(type, config)
    rules = CardBuilderSchema::REQUIRED[type] or return ""
    present = ->(key) { config[key.to_sym].present? }

    if (missing = Array(rules[:all]).reject(&present)).any?
      return dev_warning(
        missing.one? ? "Card is missing a required value" : "Card is missing required values",
        "`#{type}` cards need #{missing.map { |k| "`#{k}:`" }.to_sentence}.")
    end

    if rules[:any] && Array(rules[:any]).none?(&present)
      return dev_warning("Card has nothing to show",
        "`#{type}` cards need at least one of #{Array(rules[:any]).map { |k| "`#{k}:`" }.to_sentence(two_words_connector: ' or ', last_word_connector: ', or ')}.")
    end

    ""
  end

  # Keys the renderers read that the builder modals don't offer. Both halves of
  # the option warning depend on this being right: without them a working block
  # is told its option isn't real, and — now that a stray key can be reported as
  # belonging somewhere else — a misfiled one would name the wrong home.
  #
  # `video` is read by render_player_card, `subtitle_from_record` by
  # render_post_link (which product-link delegates to), `skus`/`variants` by
  # ProductButtonRenderer, and the collection three by the collection renderer.
  CARD_EXTRA_KEYS = {
    "player"       => %w[video],
    "post-link"    => %w[subtitle_from_record],
    "product-link" => %w[subtitle_from_record],
    # `link` is what `link_url` used to be called, and `link_text` is the label
    # for a separate call-to-action link. Neither is offered any more — the text
    # is markdown now, so a link written in it does the job with wording and
    # placement of the author's choosing — but both still render, because
    # they're sitting in posts that were written before that was true.
    "aside"        => %w[link link_text]
  }.freeze
  ACTION_EXTRA_KEYS = { "product" => %w[skus variants] }.freeze
  COLLECTION_EXTRA_KEYS = %w[part scope search].freeze

  # Every option Roe understands, grouped by the block it belongs to. Built from
  # the same schemas that drive the builder modals, so there's no second
  # vocabulary to drift out of step with the first.
  def option_contexts
    @option_contexts ||= begin
      contexts = {}

      CardBuilderSchema::FIELDS_BY_TYPE.each_key do |type|
        contexts["#{type} cards"] = card_keys_for(type)
      end

      ActionBuilderSchema::FIELDS_BY_KIND.each do |kind, fields|
        keys = fields.map { |f| f[:key] } + ACTION_EXTRA_KEYS.fetch(kind, []) + %w[for type]
        # The action renderers read `button-text` and `button_text` alike, so
        # both spellings are legitimate however the schema happens to write it.
        contexts[action_context_name(kind)] =
          keys.flat_map { |key| [ key, key.tr("-", "_"), key.tr("_", "-") ] }.uniq
      end

      contexts["collection blocks"] =
        CollectionBuilderSchema::FIELDS.map { |f| f[:key] }.uniq + COLLECTION_EXTRA_KEYS

      contexts
    end
  end

  def action_context_name(kind)
    button = ActionBuilderSchema::BUTTON_KINDS.any? { |k| k[:value] == kind }
    "#{kind} #{button ? 'buttons' : 'forms'}"
  end

  def card_keys_for(type)
    fields = CardBuilderSchema::FIELDS_BY_TYPE[type].to_a.map { |f| f[:key] }
    (fields + Array(CardBuilderSchema::CORE[type]) +
      CARD_EXTRA_KEYS.fetch(type, []) + [ "type" ]).uniq
  end

  # Options a block doesn't understand. Two different mistakes, told apart
  # because they need different answers:
  #
  #   `attribution:` on an aside  — a real option, written on the wrong block
  #   `postion:` on a pullquote   — not an option anywhere, but nearly one
  #
  # Anything else is left alone. The schemas describe what the modals offer and
  # the renderers read a few keys besides, so "unlisted" doesn't mean "wrong" —
  # and a warning that cries wolf gets ignored along with the ones that matter.
  def unrecognised_option_warnings(config, context)
    return "" unless show_block_warnings?

    known = option_contexts[context] or return ""
    strays = config.keys.map(&:to_s).reject { |key| known.include?(key) }
    return "" if strays.empty?

    misplaced, unheard_of = strays.partition { |key| other_homes(key, context).any? }
    misplaced_option_warning(misplaced, context) +
      misspelled_option_warning(unheard_of, context, known)
  end

  def other_homes(key, context)
    option_contexts.select { |name, keys| name != context && keys.include?(key) }.keys
  end

  # A key that is a real option somewhere else. No guessing involved — Roe knows
  # exactly where it belongs, so it says so rather than offering a correction.
  def misplaced_option_warning(keys, context)
    return "" if keys.empty?

    dev_warning(
      "#{'Option'.pluralize(keys.size)} from another block",
      keys.map { |key| "`#{key}:` belongs to #{homes_phrase(other_homes(key, context))}, not #{context}." }.join(" "),
      "An option a block doesn't recognize is ignored."
    )
  end

  # A common key like `text:` is valid on half a dozen blocks, and naming them
  # all buries the only part that matters: not this one.
  def homes_phrase(homes)
    return homes.to_sentence(two_words_connector: " and ", last_word_connector: ", and ") if homes.size <= 3

    "#{homes.first(2).to_sentence} and #{homes.size - 2} other blocks"
  end

  def misspelled_option_warning(keys, context, known)
    suspect = keys.filter_map { |key| (near = nearest_term(key, known)) && [ key, near ] }
    return "" if suspect.empty?

    dev_warning(
      "Unrecognised #{'option'.pluralize(suspect.size)}",
      suspect.map { |key, near| "`#{key}:` isn't an option for #{context} — did you mean `#{near}:`?" }.join(" "),
      "Unrecognized options are ignored."
    )
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

  # A style-dependent default, unless cards.yml has fixed it for every style.
  #
  # Three levels, narrowest first: the card's own `show_subtitle:` wins over
  # everything; a site setting fixes the default for all styles; with neither,
  # the style decides, which is what every install had before the setting
  # existed.
  def card_style_default(kind, key, by_style)
    fixed = CardBuilderSchema.setting_default(kind, key)
    fixed.nil? ? by_style : fixed
  end

  # Wrap a floated pullquote inside the paragraph that follows it, so text runs
  # down both sides of the quote instead of only beside its second half.
  def merge_floated_pullquotes(html)
    doc = Nokogiri::HTML::DocumentFragment.parse(html)

    doc.css(".pullquote-left, .pullquote-right").each do |pullquote|
      paragraph = pullquote.next_element
      next unless paragraph&.name == "p"

      first_half, second_half = split_paragraph_for_quote(paragraph)
      # A break with nothing on one side of it isn't a wrap, it's an empty
      # paragraph beside a quote. Leave the pullquote as its own block.
      next if first_half.empty? || second_half.empty?

      wrapper = Nokogiri::XML::Node.new("div", doc)
      wrapper["class"] = "pullquote-merge"
      wrapper.add_child(paragraph_from(doc, first_half))
      wrapper.add_child(pullquote.dup)
      wrapper.add_child(paragraph_from(doc, second_half))

      paragraph.replace(wrapper)
      pullquote.remove
    end

    doc.to_html
  end

  def paragraph_from(doc, nodes)
    paragraph = Nokogiri::XML::Node.new("p", doc)
    nodes.each { |node| paragraph.add_child(node) }
    paragraph
  end

  # Decide where the paragraph breaks, honouring a manual `||` marker if there
  # is one and otherwise picking a sentence boundary near the middle.
  #
  # The offset is measured in the paragraph's TEXT, so it can only be applied to
  # the paragraph's NODES. This used to slice the HTML string with it, which cut
  # wherever the tags had pushed that offset along: mid-word, mid-element, or
  # straight through a footnote reference's attribute list — which is how
  # `class="footnote" rel="footnote" role="doc-noteref">` came to be rendered as
  # body text in a reader's post. Text offsets and markup offsets are different
  # coordinate systems; the tags aren't in the text.
  def split_paragraph_for_quote(paragraph)
    text = paragraph.text

    marker = text.index(PULLQUOTE_SPLIT_MARKER)
    return split_children(paragraph, marker, marker + PULLQUOTE_SPLIT_MARKER.length) if marker

    point = find_split_point(text)
    return [ [], [] ] unless point

    split_children(paragraph, point, point)
  end

  # Divide a paragraph's children in two at a plain-text offset. `cut_at` ends
  # the first half and `resume_at` begins the second, so the `||` marker can be
  # dropped in the gap between them.
  def split_children(paragraph, cut_at, resume_at)
    before = []
    after = []
    consumed = 0

    paragraph.children.to_a.each do |node|
      length = node.text.length

      if consumed >= cut_at
        after << node
      elsif consumed + length <= cut_at
        before << node
      elsif node.text?
        head = node.text[0...(cut_at - consumed)].rstrip
        tail = (node.text[(resume_at - consumed)..] || "").lstrip
        before << Nokogiri::XML::Text.new(head, node.document) unless head.empty?
        after << Nokogiri::XML::Text.new(tail, node.document) unless tail.empty?
      else
        # An element straddles the break — a link, emphasis, a footnote marker.
        # There's no valid place to cut inside one, so it crosses over whole and
        # the break lands just before it.
        after << node
      end

      consumed += length
    end

    [ before, after ]
  end

  # An offset into `text`, the paragraph's plain text — never an index into
  # markup. Prefers the end of a sentence near the middle, then the nearest word
  # boundary either side of it.
  #
  # nil when there's no boundary to break on at all. The old fallback was the
  # midpoint itself, which cut whatever word happened to be there in half — a
  # one-word paragraph beside a pullquote came out as "Sho" / "rt.". A quote
  # that stays where it is reads better than a broken word.
  def find_split_point(text)
    middle = text.length / 2

    # Look for ". " near the middle (within 30% either way for more flexibility)
    search_start = [ (middle * 0.7).to_i, 0 ].max
    search_end = [ (middle * 1.3).to_i, text.length ].min

    sentence_end = text[search_start..search_end]&.index(". ")
    return search_start + sentence_end + 2 if sentence_end

    after = text.index(" ", middle)
    return after + 1 if after

    before = text.rindex(" ", middle)
    before ? before + 1 : nil
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
        when Documentation then referenced_post.public_url
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
          "No post, page, product, or documentation with url_name '#{config[:post]}' exists.",
          "Check the url_name in the content's metadata.")
      end
    end

    # `default_style` has been on the Cards settings form (and in the docs) all
    # along, but nothing read it — the fallback was a hardcoded "small". It
    # looked like it worked because the builder wrote an explicit `style:` into
    # every card it made. Now that a card at its default leaves the key out,
    # this is what the setting actually acts on.
    style = config[:style].presence ||
            SiteConfig.default("cards", "post-link")&.[]("default_style").presence ||
            "small"
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
    link_text = config[:link_text] || SiteConfig.default("cards", "post-link")&.[]("default_link_text") || "Read more →"

    # Whether the excerpt/description shows. Large shows it by default (existing
    # behaviour); small/medium only when explicitly enabled. product-link maps
    # its show_description onto this and defaults it on for all styles.
    show_excerpt = collection_truthy?(config[:show_excerpt],
      default: card_style_default(kind, "show_excerpt", style == "large"))

    # Whether the subtitle shows. Default per size: off for small (too cramped),
    # on for medium and large. Overridable with `show_subtitle:` in the card.
    show_subtitle = collection_truthy?(config[:show_subtitle],
      default: card_style_default(kind, "show_subtitle", style != "small"))

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
          show_subtitle: show_subtitle,
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
          show_subtitle: show_subtitle,
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
          show_subtitle: show_subtitle,
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

  # Render a fragment the way the document itself is rendered, so a line break,
  # a bare URL or an em dash behaves the same inside a card as outside one.
  # Footnote options are deliberately left off: a footnote defined inside a card
  # would build its own list there rather than joining the page's.
  def render_markdown_fragment(text)
    return "" if text.to_s.strip.empty?

    soft_breaks = soft_line_breaks?
    Kramdown::Document.new(
      text.to_s.strip,
      input: soft_breaks ? "GFM" : "kramdown",
      hard_wrap: soft_breaks
    ).to_html.strip
  end

  # The same, with the wrapping <p> removed, for somewhere a paragraph can't go
  # — inside a link, say. Returns nil when the text is more than one paragraph
  # and there's nothing to unwrap.
  def inline_markdown_fragment(text)
    html = render_markdown_fragment(text)
    match = html.match(%r{\A<p>(.*)</p>\z}m)
    return nil unless match
    return nil if match[1].include?("<p>")

    match[1]
  end

  # An aside is an image, some markdown, and optionally somewhere to point.
  #
  #   image:    the picture
  #   link_url: where the whole card points, image included
  #   text:     everything else, in markdown
  #
  # When it points somewhere, the card element *is* the anchor rather than
  # wrapping one around the contents — .card-aside is a grid, and an element
  # between it and its children would collapse the layout to one column. An
  # <a> can be display:grid and hold flow content, so the class list simply
  # moves onto it and every existing rule still matches.
  def render_aside(config, preview: false)
    # Asides took their text straight into the HTML, so `*emphasis*` came out
    # with the asterisks showing and a second paragraph never arrived at all.
    text = render_markdown_fragment(config[:text])
    image = config[:image].to_s
    link = config[:link_url].presence || config[:link].presence
    legacy_link_text = config[:link_text].to_s

    body = []
    body << %(<div class="aside-text">#{text}</div>) if text.present?

    # A card written before `link_url` existed, with its own call-to-action
    # label. Rendered exactly as it always was, so the post doesn't change
    # under its author; nothing in the builder writes this any more.
    if link && legacy_link_text.present?
      body << %(<a href="#{link}" class="aside-link">#{legacy_link_text}</a>)
      link = nil
    end

    # A link inside a link isn't valid and browsers unpick it badly, so the card
    # can't be one when the text already holds one. The image is outside the
    # text though, so it can still carry the link on its own — the reader gets
    # both, and neither is nested in the other.
    text_links = link && text.include?("<a ")
    link_image_only = text_links && image.present?
    notice = text_links && image.blank? ? aside_link_conflict_warning : ""

    parts = []
    if image.present?
      img = %(<img src="#{image}" alt="" class="aside-image">)
      parts << (link_image_only ? %(<a href="#{link}" class="aside-image-link">#{img}</a>) : img)
    end
    parts << "<div class=\"aside-body\">\n#{body.join("\n")}\n</div>" if body.any?

    # Whole card, or nothing — the image took it, or there was nowhere to put it.
    link = nil if text_links

    classes = [ "card", "card-aside" ]
    classes << "image-only" if image.present? && text.blank? && legacy_link_text.blank?
    classes << "aside-wrapper" if link

    open = link ? %(<a href="#{link}" class="#{classes.join(' ')}">) : %(<div class="#{classes.join(' ')}">)
    close = link ? "</a>" : "</div>"

    # {::nomarkdown} because kramdown treats <a> as inline: left to itself it
    # wraps the opening tag in a paragraph and escapes the closing one, which
    # tears the card in half. The text inside was rendered to HTML above, so
    # there is nothing here kramdown needs to look at anyway.
    [ "", "{::nomarkdown}", "#{notice}#{open}#{parts.join("\n")}#{close}", "{:/nomarkdown}", "" ].join("\n")
  end

  def aside_link_conflict_warning
    dev_warning(
      "Aside already has a link in the text.",
      "`link_url:` makes the whole card a link, but the text already has one in it — a link inside a link isn't valid. Add an image and the `link:` will be assigned to the image.",
      "Or remove `link_url:`."
    )
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
      kinds = ActionBuilderSchema::FORM_KINDS.map { |k| k[:value] }
      dev_warning("Unknown form type",
        "'#{form_type}' is not a recognised form type.#{did_you_mean(form_type, kinds)}",
        "Valid types: #{kinds.join(', ')}")
    end

    roeanji_kind_conflict_warning(config) +
      unrecognised_option_warnings(config, action_context_name(form_type)) + result.to_s
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
      "This block sets both `for: #{f}` and `type: #{t}` — `for` wins.")
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
      if show_block_warnings?
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
      #{paid_content_warnings}<!-- PAID_CONTENT_GATE -->
      <div class="paid-content-gate">
        <p>#{text}</p>
        <a href="/upgrade" class="btn-primary">#{button_text}</a>
      </div>
    HTML
  end

  # The paywall renders wherever it's written, but its upgrade button only goes
  # somewhere useful once payments actually work. Writing the block before
  # that is fine — the gate is a boundary in the article, and the preview needs
  # to show it — so this explains the gap instead of hiding the option.
  #
  # Editor previews and development only, like every other block warning; a
  # reader never sees it.
  def paid_content_warnings
    return "" unless show_block_warnings?

    unless SiteFeature.members_enabled?
      return dev_warning(
        "Without Members enabled, there is no reason for a paywall.",
        "When you enable Members, the post will cut off here for visitors, non-paid members",
        "Click `ENABLE MEMBERS` in Settings, then set this post's `audience` to `paid`."
      )
    end

    unless SiteFeature.payments_enabled?
      return dev_warning(
        "Paywall can't take payment yet",
        "The upgrade button has nowhere to send anyone until Stripe is connected.",
        "Connect Stripe in Settings → stripe.yml."
      )
    end

    return "" if audience == "paid"

    dev_warning(
      "Paywall is set on a post that is available to `everyone`",
      "Set `audience: paid` in the metadata and the paywall will hide everything below."
    )
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
          conflict: roeanji_kind_conflict_warning(config) +
            unrecognised_option_warnings(config, action_context_name(roeanji_kind(config, default: "product"))),
          start_pos: start_pos,
          end_pos: end_pos,
          match: $~
        }
      rescue => e
        Rails.logger.error "Button parsing error: #{e.message}"
        # Replace the failed button block with a dev warning
        if show_block_warnings?
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

    kinds = ActionBuilderSchema::BUTTON_KINDS.map { |k| k[:value] }
    dev_warning("Unknown button type",
      "'#{button[:kind]}' is not a recognised button type.#{did_you_mean(button[:kind], kinds)}",
      "Valid: #{kinds.join(', ')} — product is the default when no for/type is given.")
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
        "Go to Settings → Roe and click `ENABLE MEMBERS`.")
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
    # `.share` is a stable wrapper hook (a committed class) so themes can target
    # and align every share button; a `style:` value adds `.share-<token>`
    # modifiers on top. The buttons inside use btn-primary / btn-outline.
    styles     = [ "share" ] + action_button_style_classes(config, "share")
    class_attr = %( class="#{styles.join(' ')}")

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

  # Renders an amber warning box explaining why a Roe block didn't render.
  #
  #   dev_warning("Title", "What went wrong", "optional hint or context")
  #
  # Shown while writing — in development, and in an editor preview whatever the
  # environment. Silent everywhere else, which is the important half: a
  # published URL never shows these, so a reader can't be handed a diagnostic
  # and a self-hosted site can't leak one. Static builds are excluded outright
  # rather than relying on the preview flag being false, because a generated
  # file outlives the request that made it.
  #
  # Without the preview case these were invisible to anyone not running Roe
  # locally — the writer whose block silently rendered nothing got no
  # explanation at all.
  # Whether this render should explain itself. One definition, because the
  # answer is needed both here and at the call sites — several of which build an
  # expensive message, or take a different branch entirely, and shouldn't do
  # that work only for dev_warning to discard it.
  #
  # Static output is excluded outright rather than by trusting the preview flag
  # to be false: a generated file outlives the request that made it.
  def show_block_warnings?
    return false if @rendering_static

    Rails.env.development? || @rendering_preview.present?
  end

  # The closest term in `vocabulary`, or nil if nothing is close. Ruby's own
  # spell checker — the one behind NoMethodError's "did you mean?" — so the
  # threshold for "close" is the same one people already read every day, and
  # there's no similarity metric of our own to tune.
  def nearest_term(word, vocabulary)
    DidYouMean::SpellChecker.new(dictionary: vocabulary).correct(word).first
  end

  # " Did you mean 'x'?", or "" — written to sit on the end of a sentence.
  def did_you_mean(word, vocabulary)
    (near = nearest_term(word, vocabulary)) ? " Did you mean '#{near}'?" : ""
  end

  def dev_warning(title, message, hint = nil)
    return "" unless show_block_warnings?

    hint_html = hint ? "<br><span style='color:#78350f'>#{dev_warning_text(hint)}</span>" : ""
    <<~HTML
      <div style="border:2px dashed #f59e0b;padding:0.75rem 1rem;font-family:monospace;font-size:0.8rem;color:#92400e;background:#fffbeb;margin:0.5rem 0;">
        <strong>⚠️ #{dev_warning_text(title)}</strong><br>
        #{dev_warning_text(message)}#{hint_html}
      </div>
    HTML
  end

  # Escape a dev-warning string, then render `inline code` spans as <code> so
  # backticks in the copy show as highlighted code rather than literal ticks.
  def dev_warning_text(text)
    CGI.escapeHTML(text.to_s).gsub(/`([^`]+)`/) do
      "<code style=\"background:#cb863f;padding:0 0.25em;border-radius:2px;\">#{Regexp.last_match(1)}</code>"
    end
  end
end
