# What a layout draws, for the live help beside the layout editor: an HTML
# example of the page's markup, and a short description of every line and
# every [box], so moving the caret can explain what's under it.
#
# The example is built from ContentLayout's own reading of the text, so it
# can't disagree with what a page draws. The part markup is a sample — the
# element and classes each part's partial draws, with placeholder text.
#
# Descriptions are plain sentences with `code` in backticks; the editor turns
# those into <code>.

class ContentLayout
  class Explain
    PAGE_TYPES = %w[page podcast-page music-page].freeze

    def initialize(name, text)
      @name = name.to_s
      @text = text.to_s.gsub("\r\n", "\n")
      @layout = ContentLayout.parse(@name, @text)
      @kind = kind_for(@name)
    end

    def as_json(*)
      lines = line_help.transform_values do |entry|
        entry.merge(text: curly(entry[:text]), boxes: entry[:boxes].map { |b| b.merge(text: curly(b[:text])) })
      end
      { html: html_lines, warnings: @layout.warnings.map { |w| curly(w) }, lines: lines }
    end

    # The boxes the editor offers as buttons for this layout's type, in one
    # list: Roe's parts that draw something for it, then the other metadata
    # fields worth showing on a page. Each is { name:, label: "[feed links]",
    # help: }.
    def box_choices
      (parts_for_type + fields_for_type).map { |name| { name: name, label: box(name), help: curly(part_help(name)) } }
    end

    POST_PARTS = %w[title subtitle date author image feed_links excerpt tags].freeze

    # Metadata that isn't for showing on a page: settings, links to other
    # files, and IDs. Everything else a type's schema has can be a box.
    HIDDEN_FIELDS = %w[
      post_type status url_name image_in_header audience published_to audio
      video captions podcast guid explicit show_sidebar related collection
      release sku digital file_guid weight group primary page_type layout
    ].freeze

    # Post fields that only mean something on one kind of post.
    TYPE_FIELDS = {
      "duration" => %w[audio video podcast music],
      "episode_number" => %w[podcast], "season" => %w[podcast], "episode_type" => %w[podcast],
      "track_number" => %w[music], "isrc" => %w[music], "songwriters" => %w[music], "lyrics" => %w[music]
    }.freeze

    private

    # ── which kind of record the layout is for ──

    def kind_for(name)
      return "post" if Post::POST_TYPES.key?(name.to_sym)
      return "page" if PAGE_TYPES.include?(name)
      return name if %w[product documentation].include?(name)

      "post" # an extra layout, picked with `layout:` — almost always a post
    end

    def noun
      { "post" => "post", "page" => "page", "product" => "product", "documentation" => "documentation page" }[@kind]
    end

    def parts_for_type
      case @kind
      when "post"
        case @name
        when "article"                then POST_PARTS + %w[body]
        when "podcast"                then POST_PARTS + %w[player playlist body subscribe]
        when "music"                  then POST_PARTS + %w[player playlist body]
        else                               POST_PARTS + %w[player body] # audio, video, music, extra layouts
        end
      when "page"
        case @name
        when "podcast-page" then %w[podcast_title subscribe title subtitle image excerpt tags body]
        when "music-page"   then %w[release_title subscribe title subtitle image excerpt tags body]
        else                     %w[title subtitle image excerpt tags body]
        end
      when "product"       then %w[image title price buy_button tags body]
      when "documentation" then %w[title body]
      end
    end

    # The type's metadata fields, in the metadata editor's order, less the
    # ones that are settings or already a part.
    def fields_for_type
      return [] if @kind == "documentation"

      names = ContentMetadataSchema.fields_for(@kind, metadata: { "post_type" => @name }).keys
      names.reject do |field|
        HIDDEN_FIELDS.include?(field) || parts_for_type.include?(field) ||
          (@kind == "post" && Post::POST_TYPES.key?(@name.to_sym) && TYPE_FIELDS[field] && !TYPE_FIELDS[field].include?(@name))
      end
    rescue StandardError => e
      Rails.logger.warn "[ContentLayout::Explain] couldn't list fields for #{@name}: #{e.message}"
      []
    end

    # ── the HTML example ──

    # One entry per line of example markup: text, depth (indent), and which
    # block and source line drew it, so the editor can highlight the markup
    # of the line the caret is on. Entries with no block are the show page's
    # own wrapper, there for context.
    def html_lines
      out = []
      add = ->(text, depth, block: nil, line: nil) { out << { text: text, depth: depth, block: block, line: line } }

      opens = wrapper_tags
      opens.each_with_index { |tag, i| add.call(tag, i) }
      depth = opens.length

      @layout.blocks.each_with_index do |block, b|
        open, close = block_tags(block)
        if open
          add.call(open, depth, block: b, line: block.line)
          inner = depth + 1
        else
          inner = depth
        end

        block.rows.each do |row|
          if row.parts.length == 1 && row.classes.empty?
            add.call(sample(row.parts.first), inner, block: b, line: row.line)
          else
            add.call(%(<div class="#{row.classes.join(" ").presence || "layout-row"}">), inner, block: b, line: row.line)
            row.parts.each { |part| add.call(sample(part), inner + 1, block: b, line: row.line) }
            add.call("</div>", inner, block: b, line: row.line)
          end
        end

        add.call(close, depth, block: b, line: block.line) if close
      end

      opens.reverse.each_with_index { |tag, i| add.call("</#{tag[/\A<(\w+)/, 1]}>", opens.length - 1 - i) }
      out
    end

    # The elements the show page puts around the layout.
    def wrapper_tags
      case @kind
      when "post"
        type = Post::POST_TYPES.key?(@name.to_sym) ? @name : "article"
        [ %(<article class="post post-#{type}">), %(<div class="content">) ]
      when "page"          then [ %(<article class="page">) ]
      when "product"       then [ %(<div class="product">), %(<div class="content">) ]
      when "documentation" then [ %(<article class="content documentation">) ]
      end
    end

    def block_tags(block)
      css = block.classes.join(" ").presence
      case block.role
      when :header  then [ css ? %(<header class="#{css}">) : "<header>", "</header>" ]
      when :footer  then [ css ? %(<footer class="#{css}">) : "<footer>", "</footer>" ]
      when :content then css ? [ %(<div class="#{css}">), "</div>" ] : [ nil, nil ]
      else               [ %(<div class="#{css || "layout-group"}">), "</div>" ]
      end
    end

    def sample(part)
      k = @kind
      case part
      when "title"         then %(<h1 class="#{k}-title">Title</h1>)
      when "subtitle"      then %(<p class="#{k}-subtitle">Subtitle</p>)
      when "date"          then %(<time class="#{k}-date">March 5, 2026</time>)
      when "author"        then %(<span class="#{k}-author">Author</span>)
      when "image"         then %(<img class="#{k}-image">)
      when "feed_links"    then %(<div class="feed-links"><a class="feed-link">RSS</a></div>)
      when "player"        then %(<div class="post-player">…player…</div>)
      when "subscribe"     then %(<div class="podcast-subscribe">…subscribe links…</div>)
      when "playlist"      then %(<div class="post-playlist">…playlist…</div>)
      when "podcast_title" then %(<h1 class="podcast-page-title">Show name</h1>)
      when "release_title" then %(<h1 class="release-page-title">Release name</h1>)
      when "buy_button"    then %(<button class="snipcart-add-item">Add to cart</button>)
      when "price"         then %(<p class="product-price">$10.00</p>)
      when "excerpt"       then %(<p class="#{k}-excerpt">Excerpt</p>)
      when "tags"          then %(<ul class="#{k}-tags"><li class="#{k}-tag"><a class="#{k}-tag-link">tag</a></li></ul>)
      when "body"
        case k
        when "post"    then %(<div class="post-content">…the post's writing…</div>)
        when "product" then "…the product's writing…"
        else %(<div class="content">…the #{noun}'s writing…</div>)
        end
      else %(<p class="#{k}-field #{k}-#{part.dasherize}">#{part}</p>)
      end
    end

    # ── what each line and box means ──

    # line number (string, for JSON) → { text:, block:, boxes: [{ from:, to:, text: }] }
    def line_help
      rows = {}
      names = {}
      @layout.blocks.each_with_index do |block, b|
        names[block.line] = [ block, b ] if block.line
        block.rows.each { |row| rows[row.line] = [ row, block, b ] }
      end

      help = {}
      @text.split("\n", -1).each.with_index(1) do |raw, number|
        entry =
          if (problem = @layout.problems[number])
            { text: problem, problem: true }
          elsif raw.strip.empty?
            { text: "An empty line ends one block and starts the next." }
          elsif (found = names[number])
            { text: block_name_help(found.first), block: found.last }
          elsif (found = rows[number])
            row, block, b = found
            { text: row_help(row, block), block: b }
          else
            { text: "" }
          end
        entry[:boxes] = box_help(raw)
        help[number.to_s] = entry
      end
      help
    end

    def box_help(raw)
      boxes = []
      raw.scan(/\[([^\[\]]*)\]/) do
        match = Regexp.last_match
        part = match[1].strip.downcase.gsub(/\s+/, "_")
        next unless part.match?(ContentLayout::NAME_RE)

        boxes << { from: match.begin(0), to: match.end(0), text: part_help(part) }
      end
      boxes
    end

    def block_name_help(block)
      list = box_range(block.parts)
      cls = class_phrase(block.classes)
      case block.role
      when :header
        "Wraps all elments from #{list} in a `<header>` with #{cls}. The [header] is the topmost block in the layout above `[body]`"
      when :footer
        "Wraps all elemnets from #{list} in a `<footer>` with #{cls}. The [footer] is the last block in the layout below `[body]`"
      when :content
        others = block.parts - [ "body" ]
        with = others.any? ? "#{box_range(others)} and the #{noun}'s content" : "the #{noun}'s content"
        "Wraps #{with} in a `<div>` with #{cls}."
      else
        "Puts #{list} in a `<div>` with #{cls}."
      end
    end

    def row_help(row, block)
      where = place(block, @layout.blocks.index(block))
      if row.parts.length == 1 && row.classes.empty?
        "#{part_help(row.parts.first)} #{where}"
      elsif row.classes.any?
        verb = row.parts.length == 1 ? "Wraps #{box(row.parts.first)}" : "Groups #{box_list(row.parts)}"
        "#{verb} in a `<div>` with #{class_phrase(row.classes)}. #{where}"
      else
        "Groups #{box_list(row.parts)} in a `<div class=\"layout-row\">`. " \
          "To give it your own class, start the line with a name: `name: #{row.parts.map { |p| box(p) }.join(" ")}`. #{where}"
      end
    end

    # Where a block sits. A group is either between the header and the body
    # or between the body and the footer — never both.
    def place(block, index)
      case block.role
      when :header  then "It's in the header."
      when :footer  then "It's in the footer."
      when :content then "It's with the writing."
      else
        content = @layout.blocks.index { |b| b.role == :content }
        if index < content
          "It's in a group between the header and the body."
        else
          "It's in a group between the body and the footer."
        end
      end
    end

    # Straight quotes to curly ones, for display: ' → ’ (or ‘ at the start
    # of a word), " → “ ”. Text in backticks is code and stays straight,
    # so `<div class="layout-row">` can still be copied as written.
    def curly(text)
      text.to_s.split(/(`[^`]*`)/).map do |chunk|
        next chunk if chunk.start_with?("`")

        chunk
          .gsub(/(\A|[\s(\[])'/) { "#{$1}\u2018" }
          .tr("'", "\u2019")
          .gsub(/(\A|[\s(\[])"/) { "#{$1}\u201C" }
          .tr('"', "\u201D")
      end.join
    end

    def part_help(part)
      n = noun
      case part
      when "title"         then "The #{n}'s title, from `title:`."
      when "subtitle"      then "The #{n}'s subtitle, from `subtitle:`. Nothing when it has none."
      when "date"          then "The #{n}'s date, from `date:`."
      when "author"        then "The #{n}'s author, from `author:`."
      when "image"
        if @kind == "post"
          "The post's image, from `image:`. Shown only when the post has `image_in_header: true`."
        else
          "The #{n}'s image, from `image:`."
        end
      when "feed_links"    then "RSS links: the show's feed for an episode, the release's for a track, the site's for an article."
      when "player"        then "The player for the post's `audio:` or `video:`. Left out when the [body] already has a player card."
      when "body"          then "The #{n}'s content: everything below its frontmatter. A layout has one [body]."
      when "subscribe"     then "Subscribe links: Podcast and RSS links"
      when "playlist"      then "The podcast's episodes or the release's tracks. Episodic shows run newest first, serial shows oldest first, releases in track order. Left out when the `[body]` has its own playlist."
      when "podcast_title" then "The name of the podcast in this page's metadata (`podcast:`)."
      when "release_title" then "The name of the release in this page's metadata(`release:`)."
      when "buy_button"    then "The product's buy button. Left out when the `[body]` has its own `button` block."
      when "price"         then "The product's price. With `[price]` in the layout, the buy button leaves its own price off."
      when "excerpt"       then "The #{n}'s excerpt, from `excerpt:`, as written. Nothing when it has none."
      when "tags"          then "The #{n}'s tags, from `tags:`, as a list. Each one opens the site search filtered to that tag. Nothing when it has none."
      else "Shows the #{n}'s `#{part}:` field when it has one, and nothing when it doesn't."
      end
    end

    def box(part) = "[#{part.tr("_", " ")}]"

    def box_list(parts)
      boxes = parts.map { |p| box(p) }
      boxes.length <= 2 ? boxes.join(" and ") : "#{boxes[0..-2].join(", ")} and #{boxes.last}"
    end

    def box_range(parts)
      case parts.length
      when 0 then "nothing"
      when 1, 2 then box_list(parts)
      else "#{box(parts.first)} to #{box(parts.last)}"
      end
    end

    def class_phrase(classes)
      return "no class" if classes.empty?

      list = classes.map { |c| "`#{c}`" }
      classes.length == 1 ? "the class #{list.first}" : "the classes #{list[0..-2].join(", ")} and #{list.last}"
    end
  end
end
