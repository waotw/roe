# frozen_string_literal: true

# Turn a markdown list of links — the shape an imported site's header
# arrives in — into a `menu` collection block.
#
#   - [About](/about.html)      →  about          (a page: its url_name)
#   - [RSS Feed](/feed.xml)     →  [RSS Feed](/feed.xml)   (not a page: kept inline)
#
# Matching is best-guess, in confidence order: the link's path resolves to
# a page's url_name (exact, ignoring a leading slash and .html/.htm);
# then the link text slugified; then a page whose title equals the text.
# Anything unmatched is kept as an inline link, in position — a feed, an
# outside site, a page that doesn't exist yet. The builder shows each
# guess with a select so the person can correct it before anything is
# written; `convert` then rewrites just the list, leaving the rest of the
# layout as it was.
class MenuBuilder
  LINK_LINE = /\A\s*[-*+]\s+\[([^\]]*)\]\(([^)\s]+)\)\s*\z/

  Row = Struct.new(:text, :target, :url_name, :confidence, keyword_init: true) do
    # What goes in the `order:` list for this row.
    def entry = url_name.presence || "[#{text}](#{target})"
  end

  # Every page a menu could point at, as [label, url_name] — published
  # pages, alphabetical by title. What the builder's selects list.
  def self.page_options
    Page.published.map { |p| [ p.title.to_s.presence || p.url_name, p.url_name.to_s ] }
        .reject { |_, u| u.blank? }
        .sort_by { |label, _| label.downcase }
  end

  # The first run of `- [text](target)` lines in the content, with the
  # line range it occupies. nil when there's no list. Only a contiguous
  # run counts, so a stray link elsewhere in the file isn't swept up.
  def self.find_list(content)
    lines = content.to_s.split("\n", -1)
    start = lines.index { |l| l.match?(LINK_LINE) }
    return nil unless start

    finish = start
    finish += 1 while finish + 1 < lines.size && lines[finish + 1].match?(LINK_LINE)
    { start: start, finish: finish, lines: lines[start..finish] }
  end

  # One Row per link line, with a best guess for each.
  def self.rows_for(lines, pages: Page.published.to_a)
    by_url   = pages.index_by { |p| p.url_name.to_s.downcase }
    by_title = pages.index_by { |p| p.title.to_s.strip.downcase }

    lines.filter_map do |line|
      m = LINK_LINE.match(line) or next
      text, target = m[1].strip, m[2].strip
      guess, confidence = guess_for(text, target, by_url, by_title)
      Row.new(text: text, target: target, url_name: guess, confidence: confidence)
    end
  end

  def self.guess_for(text, target, by_url, by_title)
    # An outside link is never a page.
    return [ nil, :none ] if target.match?(%r{\A[a-z]+://}i)

    path_slug = target.sub(%r{\A/}, "").sub(/\.html?\z/i, "").sub(%r{/\z}, "").downcase
    return [ by_url[path_slug].url_name, :path ] if path_slug.present? && by_url[path_slug]

    text_slug = text.parameterize
    return [ by_url[text_slug].url_name, :text ] if text_slug.present? && by_url[text_slug]

    titled = by_title[text.downcase]
    return [ titled.url_name, :title ] if titled

    [ nil, :none ]
  end

  # Replace the link list in `content` with a menu block built from
  # `entries` (the confirmed order list, url_names and inline links mixed).
  # Everything outside the list's line range is untouched.
  def self.convert(content, entries:, collection:, style: nil)
    found = find_list(content) or return content

    lines = content.to_s.split("\n", -1)
    block = [ "```collection", "collection: #{collection.to_s.strip.presence || 'nav'}", "template: menu" ]
    block << "style: #{style}" if style.present?
    block << "order: #{entries.map(&:to_s).map(&:strip).reject(&:empty?).join(', ')}"
    block << "```"

    (lines[0...found[:start]] + block + lines[(found[:finish] + 1)..]).join("\n")
  end
end
