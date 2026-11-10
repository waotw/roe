# What a content type's page shows around its writing, and in what order.
#
# A layout is plain text: rows of [boxes], in blocks separated by blank lines.
#
#   post-header:
#   post-header-top: [title] [feed links]
#   [subtitle]
#   post-meta: [date] [author]
#
#   [player]
#   [body]
#
#   [subscribe]
#
# - A box is a part (see BUILT_PARTS) or a metadata field. Spaces in a name
#   are underscores: [feed links] is feed_links.
# - Boxes on one line are one row: grouped in one <div> (the row's name, or
#   .layout-row) for CSS to style. Roe doesn't lay them out itself.
# - The block holding [body] is the content: its other boxes come before or
#   after the writing. The first block in the layout is the <header> and the
#   last the <footer>, unless that block holds [body]; blocks in between are
#   groups.
# - `name:` alone on a block's first line gives that block classes;
#   `name: [a] [b]` gives one row classes. Several names, space-separated,
#   give several classes.
# Anything else is skipped with a warning, so stray text never reaches a page.
#
# Where a layout comes from, first match wins:
#   1. `layout: <name>` in the record's metadata, from the site or Roe
#   2. site/layout/content/<type>.txt — the site's own copy
#   3. Roe's default, lib/site_templates/layouts/content/<type>.txt
# so there's always one. Posts use their post_type (article, podcast, …);
# pages, products and documentation have one each.
class ContentLayout
  SITE_DIR = File.join(RoeSitePaths::SITE_LAYOUT_PATH, "content")
  ROE_DIR  = Rails.root.join("lib/site_templates/layouts/content").to_s

  # Values from the record's release (music.yml) or podcast (podcast.yml),
  # for music and podcast posts and the pages connected to them. All drawn by
  # content_layouts/parts/_series.
  RELEASE_VALUES = %w[artist release_date cover synopsis genre label copyright].freeze
  PODCAST_VALUES = %w[creator description artwork category podcast_link copyright].freeze
  SERIES_PARTS = (RELEASE_VALUES + PODCAST_VALUES).uniq.freeze

  # Parts with their own renderer (content_layouts/parts/_<name>). Any other
  # name is shown as a metadata field when the record has a value for it.
  BUILT_PARTS = (%w[
    title subtitle date author image feed_links player body subscribe
    playlist podcast_title release_title buy_button price excerpt tags
  ] + SERIES_PARTS).freeze

  NAME_RE = /\A[a-z0-9][a-z0-9_-]*\z/
  CLASS_RE = /\A[A-Za-z_][A-Za-z0-9_-]*\z/
  EXT = ".txt"

  # A line: optional `classes:` then optional [boxes]. Nothing else.
  LINE_RE = /\A(?:(?<classes>[^\[\]:]+):)?\s*(?<boxes>(?:\[[^\[\]]*\]\s*)*)\z/

  # One row of boxes (one <div> when it has several), and its classes. line is
  # where it was written (1-based), for the editor's live help.
  Row = Struct.new(:classes, :parts, :line)

  # Lines between blank lines. role is :header, :group, :content or :footer;
  # line is the line of its `name:`, if it has one.
  Block = Struct.new(:classes, :rows, :role, :line) do
    def parts = rows.flat_map(&:parts)
  end

  # problems: line number → what's wrong with it, for lines that were skipped
  # or partly skipped.
  attr_reader :name, :path, :source, :blocks, :warnings, :problems

  # Layouts named after a kind of record. `layout:` can't pick these: posts
  # imported from Jekyll often carry `layout: page` or `layout: post`, which
  # meant Jekyll's templates, not ours.
  RECORD_LAYOUTS = %w[page podcast-page music-page product documentation].freeze

  # With content layouts off (SiteConfig.content_layouts?), only Roe's
  # defaults are used: the site's files and `layout:` are ignored, not
  # removed.
  def self.for(record)
    type = type_for(record)
    custom = SiteConfig.content_layouts? && record.respond_to?(:metadata) ? record.metadata["layout"].to_s.strip : ""
    named = custom.match?(NAME_RE) && !RECORD_LAYOUTS.include?(custom) ? find(custom) : nil
    named || find(type) || find(fallback_for(record)) || empty
  end

  # The type name a record's layout file is named after. A page connected to
  # a podcast or a release has its own (page_type_for); it falls back to the
  # page layout if that file is missing.
  def self.type_for(record)
    case record
    when Post          then record.post_type.presence || "article"
    when Page          then page_type_for(record)
    when Product       then "product"
    when Documentation then "documentation"
    else record.class.name.underscore
    end
  end

  # A page connected to a podcast or a release leads with the show's or the
  # release's name and subscribe links; any other page is just its body.
  def self.page_type_for(page)
    if page.metadata["podcast"].to_s.strip.present? then "podcast-page"
    elsif page.metadata["release"].to_s.strip.present? then "music-page"
    else "page"
    end
  end

  def self.fallback_for(record)
    case record
    when Post then "article"
    when Page then "page"
    else type_for(record)
    end
  end

  # The site's copy if it has one and content layouts are on, otherwise
  # Roe's. nil when neither exists.
  def self.find(name)
    return nil unless name.to_s.match?(NAME_RE)

    site = site_path(name)
    roe  = roe_default_path(name)
    if SiteConfig.content_layouts? && File.file?(site)
      load(name, site, :site)
    elsif File.file?(roe)
      load(name, roe, :roe)
    end
  end

  def self.roe_default_path(name)
    File.join(ROE_DIR, "#{name}#{EXT}")
  end

  def self.site_path(name)
    File.join(SITE_DIR, "#{name}#{EXT}")
  end

  # Parsed layouts, kept until the file changes. A page view reads one small
  # file; this saves re-parsing it on every request.
  @cache = {}
  @cache_lock = Mutex.new

  def self.load(name, path, source)
    stat = File.stat(path)
    key = [ path, stat.mtime.to_f, stat.size ]
    @cache_lock.synchronize do
      @cache[path] = nil unless @cache[path]&.first == key
      @cache[path] ||= [ key, parse(name, File.read(path), path: path, source: source) ]
      @cache[path].last
    end
  rescue SystemCallError => e
    Rails.logger.warn "[ContentLayout] couldn't read #{path}: #{e.message}"
    nil
  end

  def self.empty
    new(name: "empty", path: nil, source: :roe,
        blocks: [ Block.new([], [ Row.new([], [ "body" ]) ], :content) ], warnings: [])
  end

  # Text → layout. Lines that aren't rows of boxes are skipped with a
  # warning; a layout without [body] gets it at the end. Never raises, so a
  # broken file still shows the writing.
  def self.parse(name, text, path: nil, source: :site)
    warnings = []
    problems = {}
    warn = lambda do |number, message|
      warnings << message
      problems[number] = [ problems[number], message ].compact.join(" ") if number
    end
    blocks = []
    current = nil
    body_seen = false

    text.to_s.gsub("\r\n", "\n").split("\n").each.with_index(1) do |raw, number|
      line = raw.strip
      if line.empty?
        current = nil
        next
      end

      match = line.match(LINE_RE)
      unless match
        warn.call(number, "Line #{number} isn't a row of [boxes], so it was skipped: #{line}")
        next
      end

      classes = class_list(match[:classes], number, warn)
      boxes = match[:boxes].scan(/\[([^\[\]]*)\]/).flatten
      current ||= Block.new([], [], nil).tap { |block| blocks << block }

      if boxes.empty?
        if current.rows.empty? && current.classes.empty?
          current.classes = classes
          current.line = number
        else
          warn.call(number, "Line #{number}: a name on its own line only works as the first line of a block.")
        end
        next
      end

      parts = boxes.filter_map do |box|
        part = box.strip.downcase.gsub(/\s+/, "_")
        if !part.match?(NAME_RE)
          warn.call(number, "Line #{number}: [#{box}] isn't a part or field name, so it was skipped.")
          next
        elsif part == "body" && body_seen
          warn.call(number, "Line #{number}: [body] is already in this layout, so this one was skipped.")
          next
        end
        body_seen ||= part == "body"
        part
      end
      current.rows << Row.new(classes, parts, number) if parts.any?
    end

    blocks.reject! { |block| block.rows.empty? }
    # A playlist only lists; a player plays it. Without one each track shows
    # the browser's own controls, which still play, so it's a warning.
    playlist_row = blocks.flat_map(&:rows).find { |row| row.parts.include?("playlist") }
    if playlist_row && blocks.flat_map(&:rows).none? { |row| row.parts.include?("player") }
      warn.call(playlist_row.line, "Line #{playlist_row.line}: [playlist] has no [player] to play it, so each track shows the browser's own controls. Add [player] above it, or a player card in the writing.")
    end
    unless body_seen
      warn.call(nil, "This layout has no [body], so the writing is shown after everything else.")
      blocks << Block.new([], [ Row.new([], [ "body" ]) ], nil)
    end
    assign_roles(blocks)

    new(name: name, path: path, source: source, blocks: blocks, warnings: warnings, problems: problems)
  end

  # Evens out indentation on save, keeping whichever way the layout already
  # does it. The rows under a block's name are either indented or not: if
  # most of them are, they all get the indentation the first one uses (two
  # spaces, a tab, …); if most aren't, none are. Names, and rows in blocks
  # without a name, start at the left edge, and blank lines are emptied.
  # A layout with no named block has nothing to go by, so it's left as is.
  # Nothing else changes: the boxes, names and order are the same text.
  def self.tidy(text)
    lines = text.to_s.gsub("\r\n", "\n").split("\n", -1)
    blocks = []
    lines.each_with_index do |line, i|
      if line.strip.empty?
        blocks << [] unless blocks.last&.empty?
      else
        blocks << [] if blocks.empty?
        blocks.last << i
      end
    end

    named_rows = blocks.select { |b| b.size > 1 && name_line?(lines[b.first]) }.flat_map { |b| b.drop(1) }
    return text.to_s if named_rows.empty?

    indented = named_rows.select { |i| lines[i].match?(/\A[ \t]/) }
    indent = indented.size * 2 >= named_rows.size ? lines[indented.first][/\A[ \t]+/] : ""

    lines.each_with_index.map do |line, i|
      body = line.sub(/\A[ \t]+/, "")
      named_rows.include?(i) && !body.empty? ? indent + body : body
    end.join("\n")
  end

  def self.name_line?(line)
    line.to_s.strip.match?(/\A[^\[\]:]+:\z/)
  end

  # The block with [body] is the content; the first block in the layout is
  # the header and the last the footer (unless it's the content), and any
  # others are groups.
  def self.assign_roles(blocks)
    content = blocks.index { |block| block.parts.include?("body") }
    blocks.each_with_index do |block, i|
      block.role =
        if i == content then :content
        elsif i.zero? then :header
        elsif i == blocks.length - 1 && i > content then :footer
        else :group
        end
    end
  end
  private_class_method :assign_roles

  def self.class_list(text, number, warn)
    names = text.to_s.split
    bad = names.reject { |n| n.match?(CLASS_RE) }
    warn.call(number, "Line #{number}: #{bad.join(", ")} can't be used as a class name, so it was left off.") if bad.any?
    names - bad
  end
  private_class_method :class_list

  def initialize(name:, path:, source:, blocks:, warnings:, problems: {})
    @name = name
    @path = path
    @source = source
    @blocks = blocks
    @warnings = warnings
    @problems = problems
  end

  def site?
    source == :site
  end

  def rows
    blocks.flat_map(&:rows)
  end

  def parts
    rows.flat_map(&:parts)
  end

  def includes?(part)
    parts.include?(part.to_s)
  end
end
