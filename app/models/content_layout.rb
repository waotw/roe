# What a content type's page shows around its writing, and in what order.
#
# A layout is a YAML list of part names, one per line, in page order:
#
#   - [title, feed_links]
#   - subtitle
#   - [date, author]
#   - player
#   - body
#
# `[a, b]` puts parts in one group (one <div>), so a theme can style them
# together. Optional front matter above the list (between `---` lines) holds
# settings for the whole layout; none are read yet.
#
# Where a layout comes from, first match wins:
#   1. `layout: <name>` in the record's metadata, from the site or Roe
#   2. site/layout/content/<type>.yml — the site's own copy
#   3. Roe's default, lib/site_templates/layouts/content/<type>.yml
# so there's always one. Posts use their post_type (article, podcast, …);
# pages, products and documentation have one each.
class ContentLayout
  SITE_DIR = File.join(RoeSitePaths::SITE_LAYOUT_PATH, "content")
  ROE_DIR  = Rails.root.join("lib/site_templates/layouts/content").to_s

  # Parts with their own renderer (content_layouts/parts/_<name>). Any other
  # name is shown as a metadata field when the record has a value for it.
  BUILT_PARTS = %w[
    title subtitle date author image feed_links player body subscribe
    episodes podcast_title buy_button price
  ].freeze

  # The player, body and what follows them sit outside a post's
  # <header class="post-header">; everything before the first of these is
  # inside it. Matches today's post page, where the player is below the header.
  BELOW_HEADER = %w[player body subscribe episodes buy_button].freeze

  NAME_RE = /\A[a-z0-9][a-z0-9_-]*\z/

  attr_reader :name, :path, :source, :settings, :groups, :warnings

  # Layouts named after a kind of record. `layout:` can't pick these: posts
  # imported from Jekyll often carry `layout: page` or `layout: post`, which
  # meant Jekyll's templates, not ours.
  RECORD_LAYOUTS = %w[page product documentation].freeze

  def self.for(record)
    type = type_for(record)
    custom = record.respond_to?(:metadata) ? record.metadata["layout"].to_s.strip : ""
    named = custom.match?(NAME_RE) && !RECORD_LAYOUTS.include?(custom) ? find(custom) : nil
    named || find(type) || find(fallback_for(record)) || empty
  end

  # The type name a record's layout file is named after.
  def self.type_for(record)
    case record
    when Post          then record.post_type.presence || "article"
    when Page          then "page"
    when Product       then "product"
    when Documentation then "documentation"
    else record.class.name.underscore
    end
  end

  def self.fallback_for(record)
    record.is_a?(Post) ? "article" : type_for(record)
  end

  # The site's copy if it has one, otherwise Roe's. nil when neither exists.
  def self.find(name)
    return nil unless name.to_s.match?(NAME_RE)

    site = File.join(SITE_DIR, "#{name}.yml")
    roe  = File.join(ROE_DIR, "#{name}.yml")
    if File.file?(site)
      load(name, site, :site)
    elsif File.file?(roe)
      load(name, roe, :roe)
    end
  end

  def self.roe_default_path(name)
    File.join(ROE_DIR, "#{name}.yml")
  end

  def self.site_path(name)
    File.join(SITE_DIR, "#{name}.yml")
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
    new(name: "empty", path: nil, source: :roe, settings: {}, groups: [ [ "body" ] ], warnings: [])
  end

  # Text → layout. A file that can't be read as a list falls back to the body
  # alone, with a warning, rather than breaking the page.
  def self.parse(name, text, path: nil, source: :site)
    warnings = []
    settings_text, list_text = split_front_matter(text.to_s)

    settings = settings_text ? safe_yaml(settings_text, warnings, "settings") : {}
    settings = {} unless settings.is_a?(Hash)

    list = safe_yaml(list_text, warnings, "list")
    unless list.is_a?(Array)
      warnings << "The layout isn't a list of parts, so only the body is shown." unless list.nil?
      list = []
    end

    groups = list.filter_map do |item|
      names = Array(item).map { |n| n.to_s.strip }.reject(&:empty?)
      if names.empty? || !names.all? { |n| n.match?(NAME_RE) }
        warnings << "Skipped #{item.inspect}: a part is one name, or a group like [title, subtitle]."
        next
      end
      names
    end

    unless groups.flatten.include?("body")
      warnings << "This layout has no body, so the writing is shown after everything else."
      groups << [ "body" ]
    end

    new(name: name, path: path, source: source, settings: settings, groups: groups, warnings: warnings)
  end

  # `---\nsettings\n---\nlist` → [settings, list]; no front matter → [nil, text].
  def self.split_front_matter(text)
    match = text.match(/\A---[ \t]*\r?\n(.*?)^---[ \t]*\r?\n?(.*)\z/m)
    match ? [ match[1], match[2] ] : [ nil, text ]
  end

  def self.safe_yaml(text, warnings, what)
    YAML.safe_load(text.to_s)
  rescue Psych::Exception => e
    warnings << "The layout's #{what} couldn't be read: #{e.message}"
    nil
  end
  private_class_method :safe_yaml

  def initialize(name:, path:, source:, settings:, groups:, warnings:)
    @name = name
    @path = path
    @source = source
    @settings = settings
    @groups = groups
    @warnings = warnings
  end

  def site?
    source == :site
  end

  def parts
    groups.flatten
  end

  def includes?(part)
    parts.include?(part.to_s)
  end
end
