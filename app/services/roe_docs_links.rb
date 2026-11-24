# frozen_string_literal: true

# The links check for Roe's own docs (site/documentation/roe), the ones that
# ship with every release. Same checks as the site's (LinkCheck), read from
# the files themselves, so bin/release can run it without Rails and see a
# fix the moment it's saved.
#
# What counts, as the docs site reads it:
#
#   [[x]], [text](x.md)               never links: Roe's docs aren't linkable
#                                     by file (InternalLinks), so these show
#                                     as plain text
#   [text](/documentation/roe/x)      a doc with that url_name
#   card post:, order:, related:      a doc's url_name or file name
#   /media/...                        a file in the docs' own media folder,
#                                     since that's the one that ships
#
# Other addresses (`/admin`, `/posts/x`) belong to whatever site the docs
# are on, so they aren't checked.
#
# DEPENDENCY-FREE ON PURPOSE, like MarkdownDoctor: bin/roe-docs-links and
# bin/release require it without booting Rails.
require "yaml"
require "date"
require_relative "markdown_doctor"

class RoeDocsLinks
  Doc = Struct.new(:file, :name, :url_name, :status, :related, :body, :body_start, keyword_init: true)

  TYPES = {
    broken_internal_link: "links",
    unclear_internal_link: "links",
    unclear_name: "links",
    draft_link: "drafts",
    missing_media: "media",
    site_name: "site"
  }.freeze
  # Listed, but they don't fail the check: a name that could mean two
  # things still works, and a site's own post or page in an example works
  # wherever the site has it.
  WARNINGS = %i[unclear_internal_link unclear_name site_name].freeze
  IN_DRAFTS = "in_drafts"

  attr_reader :dir, :problems, :links, :media

  def initialize(dir)
    @dir = dir
    @problems = []
    @links = 0
    @media = 0
  end

  def docs
    @docs ||= Dir.glob(File.join(@dir, "**", "*.md")).sort
                 .reject { |file| file.delete_prefix(@dir).start_with?("/media/") }
                 .map { |file| read(file) }
  end

  def call
    docs.each do |doc|
      MarkdownDoctor.diagnose(doc.body, **counted(options)).each do |issue|
        next unless TYPES.key?(issue[:type])

        add(doc, issue, line: doc.body_start + issue[:line])
      end
      check_related(doc)
    end
    self
  end

  # Something to fix: anything but a name that could mean two things (it
  # still works) or a problem inside a draft (nobody sees it yet).
  def broken?
    @problems.any? { |p| self.class.blocking?(p) }
  end

  def self.blocking?(problem)
    !problem[:warning] && problem[:section] != IN_DRAFTS
  end

  # The report `roe links` and bin/release print. Same shape as the site's
  # (LinkCheck::Report).
  def report_lines
    self.class.report_lines(
      heading: "ROE DOCS  #{docs.size} files · #{@links} links · #{@media} media files",
      problems: @problems
    )
  end

  # problems: [{ section:, warning:, where:, message: }]
  def self.report_lines(heading:, problems:)
    lines = [ heading, "" ]
    # COPY: report sections
    listed_only = [ IN_DRAFTS, "site" ]
    [ [ "media", "MISSING MEDIA" ], [ "links", "BROKEN LINKS" ], [ "drafts", "LINKS TO DRAFTS" ],
      [ IN_DRAFTS, "IN DRAFTS (listed only, nothing is blocked)" ],
      [ "site", "NEEDS THE SITE'S OWN POSTS OR PAGES (listed only, nothing is blocked)" ] ].each do |section, title|
      rows = problems.select { |p| p[:section] == section }
      next if listed_only.include?(section) && rows.empty?

      lines << (listed_only.include?(section) ? title.sub("(", "(#{rows.size}, ") : "#{title} (#{rows.count { |p| !p[:warning] }})")
      rows.each do |p|
        lines << "  #{p[:where]}"
        lines << "    #{warning_note(p)}#{p[:message]}"
      end
      lines << ""
    end
    lines
  end

  # COPY: report notes for problems that don't fail the check
  def self.warning_note(problem)
    return "" unless problem[:warning] && problem[:type].to_s != "site_name"

    "(still works) "
  end

  private

  def options
    {
      link_status: ->(_target) { [ :missing, nil ] },
      name_matches: ->(name) { find(name).map { |doc| "the doc “#{doc.name}”" } },
      address_status: ->(path) { address_status(path) },
      media_exists: ->(path) { File.file?(File.join(@dir, "media", path.delete_prefix("/media/"))) },
      # A card names a site's post; a list names the site's pages unless its
      # source is the docs.
      site_names: ->(kind, source) { kind == :card || !source.to_s.strip.start_with?("documentation") }
    }
  end

  # Every reference asked about is counted. site_names isn't a reference:
  # it says where names can be checked.
  def counted(opts)
    opts.to_h do |key, callable|
      next [ key, callable ] if key == :site_names

      [ key, ->(value) { key == :media_exists ? @media += 1 : @links += 1; callable.call(value) } ]
    end
  end

  def address_status(path)
    name = path[%r{\A/documentation/roe/([^/?#]+)/?\z}, 1]
    return [ :ok, nil ] unless name

    doc = docs.find { |d| d.url_name == name }
    return [ :missing, nil ] unless doc

    [ doc.status == "draft" ? :draft : :ok, doc ]
  end

  # A doc's url_name first, then its file name (ItemName's rule), with or
  # without `documentation/roe/` and `.md`.
  def find(name)
    plain = name.to_s.strip.delete_prefix("/").delete_prefix("documentation/").delete_prefix("roe/")
    file = plain.match?(/\.md\z/i)
    plain = plain.sub(/\.md\z/i, "").downcase
    by_url = file ? [] : docs.select { |d| d.url_name.to_s.downcase == plain }
    (by_url + docs.select { |d| File.basename(d.file, ".md").downcase == plain }).uniq
  end

  def check_related(doc)
    names = doc.related.is_a?(String) ? doc.related.split(",") : Array(doc.related)
    names.map { |n| n.to_s.strip }.reject { |n| n.empty? || %w[true false].include?(n) }.each do |name|
      @links += 1
      found = find(name)
      # COPY: related: message
      next if found.size == 1

      if found.empty?
        add(doc, { type: :broken_internal_link, message: "#{name} doesn't match a doc, so it's left out of related items" }, field: "related")
      else
        add(doc, { type: :unclear_name, message: "#{name} could be #{found.map { |d| "the doc “#{d.name}”" }.join(' or ')}" }, field: "related")
      end
    end
  end

  def add(doc, issue, line: nil, field: nil)
    file = doc.file.delete_prefix("#{@dir}/")
    @problems << {
      section: doc.status == "draft" ? IN_DRAFTS : TYPES.fetch(issue[:type]),
      type: issue[:type],
      warning: WARNINGS.include?(issue[:type]),
      file: file,
      line: line,
      field: field,
      where: field ? "#{file} (#{field}:)" : "#{file}:#{line}",
      message: issue[:message]
    }
  end

  # A doc without a url_name gets its title's (HasMetadata#calculate_url_name,
  # which is ActiveSupport's parameterize: accents dropped, anything else
  # that isn't a letter or digit becomes one dash).
  def url_name_for(title)
    text = title.to_s.unicode_normalize(:nfkd).encode("ASCII", invalid: :replace, undef: :replace, replace: "")
    slug = text.downcase.gsub(/[^a-z0-9\-_]+/, "-").gsub(/-{2,}/, "-").gsub(/\A-|-\z/, "")
    slug.empty? ? nil : slug
  end

  # Front matter and body. Line numbers are reported in the file, so the
  # body's first line is offset by the front matter's.
  def read(file)
    text = File.read(file)
    meta = {}
    body = text
    start = 0
    if (m = text.match(/\A---[ \t]*\r?\n(.*?)\r?\n---[ \t]*(?:\r?\n|\z)/m))
      meta = (YAML.safe_load(m[1], permitted_classes: [ Date, Time ]) rescue {}) || {}
      body = m.post_match
      start = m[0].count("\n")
    end
    Doc.new(file: file, name: (meta["title"] || File.basename(file, ".md")).to_s,
            url_name: (meta["url_name"] || url_name_for(meta["title"]) || File.basename(file, ".md")).to_s,
            status: meta["status"].to_s, related: meta["related"], body: body, body_start: start)
  end
end
