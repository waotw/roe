# The site-wide links check: every reference in the site's posts, pages,
# products and docs to another item or a media file, and which of them
# point at nothing. The dashboard's LINKS box and the Links page show the
# last result; `roe links` prints it.
#
# What's checked, each the way the page reads it (LinkTargets):
#
#   [[posts/x]], [text](/posts/x.md)     links to a file
#   [text](/posts/x), href="/about"      links to an address
#   card post:/product:, order:          names in the text
#   related:                             names in the metadata
#   /media/... in the text and metadata  media files
#
# The header, footer and sidebar layouts are checked too: their menus name
# pages in `order:`.
#
# Links to other sites are never checked. Roe's own docs (documentation/roe)
# aren't part of the site's check; RoeDocsLinks checks those for releases.
#
# It runs at startup and after every change the file watcher hears (a save,
# an upload, a rename, an edit made outside Roe), in the background, and
# when CHECK NOW is pressed. The result is kept in tmp/, not site/: each
# install checks its own content, and Site Sync has nothing to carry.
class LinkCheck
  STORE = Rails.root.join("tmp", Rails.env.test? ? "link_check-test.json" : "link_check.json")

  # Changes close together (a save writes the file and its media) are
  # checked once, after they settle.
  DELAY = 2

  SECTIONS = {
    missing_media: "media",
    broken_internal_link: "links",
    unclear_internal_link: "links",
    unclear_name: "links",
    draft_link: "drafts"
  }.freeze
  # Could mean two things: the link still works, so it's listed but not
  # counted as broken.
  WARNINGS = %i[unclear_internal_link unclear_name].freeze

  @lock = Mutex.new

  class << self
    # The last result, or nil before the first check.
    def latest
      return nil unless File.exist?(STORE)

      JSON.parse(File.read(STORE))
    rescue JSON::ParserError, SystemCallError
      nil
    end

    # Check now and keep the result.
    def run!(reason: "check")
      result = new.call.merge("checked_at" => Time.current.iso8601, "reason" => reason)
      write(result)
      result
    end

    # Check soon, in the background. Requests that arrive while a check is
    # waiting or running are folded into one more check afterwards. Not in
    # tests: they call run! themselves.
    def request(reason)
      return if Rails.env.test?

      @lock.synchronize do
        @pending = reason
        return if @worker&.alive?

        @worker = Thread.new { work }
      end
    end

    # `roe links`: check the site now, then Roe's docs, and print both.
    # Returns the exit status: 1 when either has something broken (a name
    # that could mean two things still works, so it doesn't count).
    def cli(io = $stdout)
      result = run!(reason: "command")
      site = site_problems(result)
      docs = RoeDocsLinks.new(File.join(RoeSitePaths::SITE_PATH, "documentation", "roe")).call

      # COPY: roe links heading
      io.puts RoeDocsLinks.report_lines(heading: "SITE  #{result.dig('counts', 'total')} links and media files", problems: site)
      io.puts docs.report_lines
      broken = site.any? { |p| !p[:warning] } || docs.broken?
      # COPY: roe links last line
      io.puts broken ? "Something is broken: fix it, then run roe links again." : "Nothing broken."
      broken ? 1 : 0
    end

    # The stored problems in the report's shape (RoeDocsLinks.report_lines).
    def site_problems(result)
      result["problems"].map do |p|
        kind = p["item_type"] == "Documentation" ? "doc" : p["item_type"].downcase
        kind += ", draft" if p["draft"]
        where = p["field"] ? "#{p['field']}:" : "line #{p['line']}"
        { section: p["section"], warning: p["warning"], where: "#{p['title']} (#{kind}) · #{where}", message: p["message"] }
      end
    end

    private

    def work
      loop do
        sleep DELAY
        reason = @lock.synchronize { @pending.tap { @pending = nil } }
        break unless reason

        Rails.application.executor.wrap { run!(reason: reason) }
      end
    rescue StandardError => e
      Rails.logger.error("[LinkCheck] #{e.class}: #{e.message}")
    end

    def write(result)
      FileUtils.mkdir_p(File.dirname(STORE))
      temp = "#{STORE}.#{Process.pid}.tmp"
      File.write(temp, JSON.pretty_generate(result))
      File.rename(temp, STORE)
    end
  end

  def initialize
    @links = 0
    @media = 0
    @problems = []
  end

  def call
    records.each { |record| check(record) }
    layouts.each { |key, path| check_layout(key, path) }
    {
      "counts" => counts,
      "problems" => @problems.sort_by { |p| [ p["section"], p["title"].to_s.downcase, p["line"].to_i ] }
    }
  end

  private

  def records
    models = [ Post, Page, Documentation ]
    models << Product if SiteFeature.store_enabled?
    models.flat_map do |model|
      scope = model.all
      scope = scope.where("file_path NOT LIKE ?", "%/documentation/roe/%") if model == Documentation
      scope.to_a
    end
  end

  # The header, footer and sidebar: on every page, and the menus in them
  # name pages by `order:`. Files, not records, so they're read from disk.
  def layouts
    LayoutFiles::KEYS.filter_map { |key| [ key, LayoutFiles.path(key) ] if LayoutFiles.exist?(key) }
  end

  def check_layout(key, path)
    item = { "item_type" => "Layout", "item_id" => key, "title" => key.capitalize, "draft" => false }
    MarkdownDoctor.diagnose(File.read(path), **counted_options).each do |issue|
      add(item, issue, line: issue[:line]) if SECTIONS.key?(issue[:type])
    end
  rescue StandardError => e
    Rails.logger.warn("[LinkCheck] layout #{key}: #{e.class}: #{e.message}")
  end

  def check(record)
    MarkdownDoctor.diagnose(record.content.to_s, **counted_options).each do |issue|
      next unless SECTIONS.key?(issue[:type])

      add(record, issue, line: issue[:line])
    end
    check_metadata(record)
  rescue StandardError => e
    Rails.logger.warn("[LinkCheck] #{record.class.name} #{record.id}: #{e.class}: #{e.message}")
  end

  # Media files in any metadata field, and the names in `related:`.
  def check_metadata(record)
    each_value(record.metadata) do |field, value|
      path = value.strip
      next unless path.start_with?("/media/") && !path.match?(/\]\(|=\s*["']|\n/)

      @media += 1
      next if LinkTargets.media_exists?(path.split(/[?#]/, 2).first)

      # COPY: missing media message (metadata)
      add(record, { type: :missing_media, target: path, message: "#{path} isn't in the media library" }, field: field)
    end

    related_names(record.metadata["related"]).each do |name|
      @links += 1
      found = LinkTargets.name_matches(name)
      # COPY: related: messages
      if found.empty?
        add(record, { type: :broken_internal_link, target: name,
                      message: "#{name} doesn't match a post, page, product or doc, so it's left out of related items" }, field: "related")
      elsif found.size > 1
        names = found.map { |match| LinkTargets.describe(match) }
        add(record, { type: :unclear_name, target: name,
                      message: "#{name} could be #{names.join(' or ')}. Roe uses #{names.first}. Add the folder to clarify which #{name}" }, field: "related")
      end
    end
  end

  def related_names(value)
    list = value.is_a?(String) ? value.split(",") : Array(value)
    list.map { |name| name.to_s.strip }.reject { |name| name.empty? || %w[true false].include?(name) }
  end

  # [field, string] for every string in the metadata, nested or not. The
  # field is the key that holds it, so the editor can open that field.
  def each_value(node, key = nil, &block)
    case node
    when String then yield key, node if key
    when Hash then node.each { |k, v| each_value(v, k.to_s, &block) }
    when Array then node.each { |v| each_value(v, key, &block) }
    end
  end

  # item: a record, or a layout's own { "item_type", "item_id", ... }.
  def add(item, issue, line: nil, field: nil)
    item = item_for(item) unless item.is_a?(Hash)
    @problems << item.merge(
      "section" => SECTIONS.fetch(issue[:type]),
      "type" => issue[:type].to_s,
      "warning" => WARNINGS.include?(issue[:type]),
      "line" => line,
      "field" => field,
      "target" => issue[:target].to_s,
      "message" => issue[:message].to_s
    )
  end

  def item_for(record)
    {
      "item_type" => record.class.name,
      "item_id" => record.id,
      "title" => record.title.to_s.presence || File.basename(record.file_path.to_s, ".md"),
      "draft" => !record.published?
    }
  end

  def counts
    by = ->(section, warning: false) { @problems.count { |p| p["section"] == section && p["warning"] == warning } }
    {
      "media" => by.call("media"),
      "broken" => by.call("links"),
      "unclear" => by.call("links", warning: true),
      "drafts" => by.call("drafts"),
      "total" => @links + @media
    }
  end

  # LinkTargets' callables, counting every reference they're asked about.
  def counted_options
    LinkTargets.doctor_options.to_h do |key, callable|
      counted = lambda do |value|
        key == :media_exists ? @media += 1 : @links += 1
        callable.call(value)
      end
      [ key, counted ]
    end
  end
end
