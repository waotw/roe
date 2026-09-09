require "yaml"

# Parses a single markdown or HTML file into a normalized FilesImporter::Document.
# Pure: string (+ its source path) in, Document out. No writing, no DB.
class FilesImporter::Parser
  MARKDOWN_EXTS = %w[.md .markdown .mdown].freeze
  HTML_EXTS     = %w[.html .htm].freeze

  # Frontmatter keys Roe maps to first-class fields; everything else is kept
  # as a custom field.
  MAPPED_KEYS = %w[
    title date slug permalink tags author subtitle
    summary excerpt description layout type status published draft
  ].freeze

  JEKYLL_DATE = /\A(\d{4}-\d{2}-\d{2})-/
  AUDIO_LINK  = /\.(?:mp3|m4a|m4b|aac|wav|ogg|oga|opus|flac)(?![a-z0-9])/i
  EPISODE_DIRS = %w[audio podcast podcasts episode episodes].freeze

  def initialize(converter: SubstackImporter::Converter.new(insert_paywalls: false))
    @converter = converter
  end

  def self.content_file?(path)
    ext = File.extname(path).downcase
    MARKDOWN_EXTS.include?(ext) || HTML_EXTS.include?(ext)
  end

  # abs_path: file on disk to read; source_path: its path relative to the
  # import root (used for the preserved filename, dedup, and classification).
  def parse(abs_path, source_path)
    content = File.read(abs_path)
    if MARKDOWN_EXTS.include?(File.extname(abs_path).downcase)
      parse_markdown(content, source_path)
    else
      parse_html(content, source_path)
    end
  end

  # ── Markdown ────────────────────────────────────────────────────────────
  def parse_markdown(content, source_path)
    fm, body = split_frontmatter(content)
    body = body.to_s.strip
    basename = File.basename(source_path, ".*")
    jekyll_date = basename[JEKYLL_DATE, 1]
    date = fm["date"].to_s.strip.presence || jekyll_date

    FilesImporter::Document.new(
      source_path: source_path,
      format:      :markdown,
      basename:    basename,
      title:       fm["title"].to_s.strip.presence || first_heading(body) || humanize(basename),
      slug:        (fm["slug"].presence || fm["permalink"].presence)&.to_s&.strip.presence,
      date:        date,
      tags:        normalize_tags(fm["tags"]),
      author:      fm["author"].to_s.strip.presence,
      subtitle:    fm["subtitle"].to_s.strip.presence,
      excerpt:     (fm["summary"].presence || fm["excerpt"].presence || fm["description"].presence)&.to_s&.strip,
      body:        body,
      custom:      fm.except(*MAPPED_KEYS),
      type_hint:   type_hint(fm),
      dated:       date.present?,
      episode_like: episode_like?(source_path, body, fm["audio"], fm["enclosure"])
    )
  end

  # ── HTML ────────────────────────────────────────────────────────────────
  def parse_html(content, source_path)
    doc = Nokogiri::HTML(content)
    basename = File.basename(source_path, ".*")

    # Prefer the semantic main content; strip chrome before converting so nav
    # links and scripts don't bleed into the body.
    main = doc.at_css("main") || doc.at_css("article") || doc.at_css("body") || doc
    main.css("nav, header, footer, script, style, noscript").remove

    title = doc.at_css("title")&.text&.strip.presence ||
            doc.at_css("h1")&.text&.strip.presence
    date  = meta(doc, property: "article:published_time") ||
            doc.at_css("time[datetime]")&.[]("datetime")&.strip.presence

    FilesImporter::Document.new(
      source_path: source_path,
      format:      :html,
      basename:    basename,
      title:       title.presence || humanize(basename),
      slug:        nil,
      date:        date,
      tags:        [],
      author:      meta(doc, name: "author"),
      subtitle:    nil,
      excerpt:     meta(doc, name: "description"),
      body:        @converter.convert(main.inner_html).to_s.strip,
      custom:      {},
      type_hint:   nil,
      dated:       date.present?,
      episode_like: episode_like?(source_path, content)
    )
  end

  private

  # Flags files that look like podcast episodes (an <audio> element or a link
  # to an audio file, or an audio/podcast folder) so the review can suggest
  # importing them via Feed Imports instead of as articles/pages.
  def episode_like?(source_path, *texts)
    dirs = File.dirname(source_path).split("/").map(&:downcase)
    return true if (dirs & EPISODE_DIRS).any?
    texts.any? { |t| t.to_s.match?(/<audio\b/i) || t.to_s.match?(AUDIO_LINK) }
  end

  def split_frontmatter(content)
    if content =~ /\A\s*---\s*\n(.*?)\n---\s*\n?(.*)\z/m
      parsed = YAML.safe_load($1, permitted_classes: [ Date, Time ]) rescue nil
      fm = parsed.is_a?(Hash) ? parsed.transform_keys(&:to_s) : {}
      [ fm, $2 ]
    else
      [ {}, content ]
    end
  end

  def type_hint(fm)
    value = (fm["type"].presence || fm["layout"].presence).to_s.downcase
    return "post" if %w[post posts article articles episode].include?(value)
    return "page" if value == "page"
    nil
  end

  def normalize_tags(value)
    case value
    when Array then value.map { |t| t.to_s.strip }.reject(&:empty?)
    when String then value.split(/[,\s]+/).map(&:strip).reject(&:empty?)
    else []
    end
  end

  def first_heading(body)
    body.to_s[/^\#{1,6}\s+(.+)$/, 1]&.strip
  end

  def humanize(basename)
    basename.to_s.sub(JEKYLL_DATE, "").tr("-_", "  ").strip.split.map(&:capitalize).join(" ")
  end

  def meta(doc, name: nil, property: nil)
    selector = name ? "meta[name='#{name}']" : "meta[property='#{property}']"
    doc.at_css(selector)&.[]("content")&.strip.presence
  end
end
