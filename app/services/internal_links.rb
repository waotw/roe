# Links between a site's own content, by file.
#
# A post, page, product or doc is named by its file: the path under site/,
# without `.md` — `posts/lab-full`, `pages/members/donate`. Files don't move
# when a title or url_name changes, so a link written this way keeps working
# while the address it points at changes. Two ways to write one:
#
#   [[posts/lab-full]]                 wikilink; shows the item's title
#   [[posts/lab-full|the lab post]]    wikilink with its own text
#   [the lab post](/posts/lab-full.md) Markdown link to the file
#
# The folder may be left off (`[[lab-full]]`) when only one file has that
# name. `#heading` after the name links to a heading on that page.
#
# On the site each becomes an ordinary link to the item's address. A link to
# something that doesn't exist, or isn't published, shows as its text.
#
# Roe's own docs (documentation/roe) aren't linkable: they're Roe's, not the
# site's, and they change with every update.
module InternalLinks
  MODELS = { "posts" => "Post", "pages" => "Page", "products" => "Product", "documentation" => "Documentation" }.freeze

  # [[target]] or [[target|text]]. The target can't hold [ ] | or a line
  # break; the text can't hold [ ] or a line break.
  WIKILINK = /\[\[([^\[\]|\n]+?)(?:\|([^\[\]\n]*))?\]\]/
  # An href ending in .md (with an optional #anchor) that isn't another site.
  MD_HREF = %r{\A(?!(?:[a-z][a-z0-9+.-]*:)|//)([^?#]+?\.md)(#.*)?\z}i

  Item = Struct.new(:model, :id, :ref, keyword_init: true) do
    def record = model.constantize.find_by(id: id)
  end

  module_function

  # The record a link names, or nil.
  def resolve(target)
    item = lookup(target)
    item.is_a?(Item) ? item.record : nil
  end

  # What a link names, and whether it can be followed:
  #   [:ok, record]  [:draft, record]  [:missing, nil]  [:ambiguous, [refs]]
  def status(target)
    item = lookup(target)
    return [ :ambiguous, item ] if item.is_a?(Array)
    return [ :missing, nil ] unless item

    record = item.record
    return [ :missing, nil ] unless record

    [ record.published? ? :ok : :draft, record ]
  end

  # `posts/lab-full#notes` → ["posts/lab-full", "#notes"]. Leading slash and
  # `.md` are optional.
  def split(target)
    ref, anchor = target.to_s.strip.split("#", 2)
    ref = ref.to_s.strip.delete_prefix("/").sub(/\.md\z/i, "")
    [ ref, anchor.present? ? "##{anchor.strip}" : "" ]
  end

  # The address a link should go to, or nil when it shows as text.
  def href(target)
    state, record = status(target)
    return nil unless state == :ok

    record.public_url + split(target).last
  end

  # The file name a record is linked by: `posts/lab-full`.
  def ref_for(record)
    path = record.file_path.to_s
    path = path.start_with?("/") ? relative(path) : path
    path&.sub(/\.md\z/i, "")
  end

  # Every linkable item, for the editor's list. Products only when the store
  # is on.
  def listing
    store = SiteFeature.store_enabled?
    MODELS.values.flat_map do |name|
      next [] if name == "Product" && !store

      name.constantize.select(:id, :metadata, :file_path, :updated_at).filter_map do |record|
        ref = ref_for(record)
        next unless ref && linkable_ref?(ref)

        {
          title: record.title.to_s.presence || File.basename(ref),
          ref: ref,
          url_name: record.url_name.to_s,
          address: record.public_url.to_s,
          draft: !record.published?,
          updated: record.updated_at.to_i
        }
      end
    end
  end

  # ── Rendering ────────────────────────────────────────────────────────────

  # Swaps each wikilink in Markdown for a placeholder, kept in `store`, so
  # kramdown never sees the brackets or the pipe (which would split a table
  # cell). Inline code is left alone. #restore puts the HTML back.
  def protect(markdown, store)
    return markdown unless markdown.include?("[[")

    markdown.gsub(/(`+)(?:(?!\1).)+?\1|#{WIKILINK}/m) do
      match = Regexp.last_match
      next match[0] if match[1]

      token = "ROEWIKILINK#{store.size}X"
      store[token] = link_html(match[2], match[3])
      token
    end
  end

  def restore(html, store)
    return html if store.empty?

    html.gsub(/ROEWIKILINK\d+X/) { |token| store.fetch(token, token) }
  end

  # `<a href="/posts/lab-full.md">` → the post's address. A link to a file
  # that's missing or not published keeps its text and loses the link.
  def rewrite_file_hrefs(html)
    return html unless html.include?(".md")

    html.gsub(%r{<a\s+href="([^"]*)"([^>]*)>(.*?)</a>}m) do
      match = Regexp.last_match
      target = CGI.unescapeHTML(match[1])
      next match[0] unless target.match?(MD_HREF)

      url = href(target)
      url ? %(<a href="#{ERB::Util.html_escape(url)}"#{match[2]}>#{match[3]}</a>) : match[3]
    end
  end

  def link_html(target, text)
    state, record = status(target)
    label = text.to_s.strip.presence || (record&.title.to_s.presence) || split(target).first
    label = ERB::Util.html_escape(label)
    return label unless state == :ok

    %(<a href="#{ERB::Util.html_escape(record.public_url + split(target).last)}">#{label}</a>)
  end

  # Plain text for a wikilink: its text, or the item's title. For search and
  # excerpts, where a link can't be.
  def plain(text)
    return text unless text.to_s.include?("[[")

    text.gsub(WIKILINK) do
      label = Regexp.last_match(2).to_s.strip.presence
      label || resolve(Regexp.last_match(1))&.title.presence || split(Regexp.last_match(1)).first
    end
  end

  # ── Lookup ───────────────────────────────────────────────────────────────

  # An Item, an Array of refs when a folderless name matches several, or nil.
  def lookup(target)
    ref, = split(target)
    return nil if ref.empty?

    by_ref, by_name = index
    return by_ref[ref] if ref.include?("/")

    found = by_name[ref] || []
    found.size > 1 ? found.map(&:ref) : found.first
  end

  # { ref => Item } and { basename => [Item] }, rebuilt when any content
  # changes. Built from ids and paths only, so it stays cheap.
  def index
    version = MODELS.values.map { |name| model = name.constantize; [ model.count, model.maximum(:updated_at).to_f ] }
    @index_lock ||= Mutex.new
    @index_lock.synchronize do
      return @index if @index_version == version

      by_ref = {}
      by_name = Hash.new { |h, k| h[k] = [] }
      MODELS.each_value do |name|
        name.constantize.pluck(:id, :file_path).each do |id, path|
          ref = path.to_s.start_with?("/") ? relative(path)&.sub(/\.md\z/i, "") : path.to_s.sub(/\.md\z/i, "")
          next if ref.blank? || !linkable_ref?(ref)

          item = Item.new(model: name, id: id, ref: ref)
          by_ref[ref] = item
          by_name[File.basename(ref)] << item
        end
      end
      @index_version = version
      @index = [ by_ref, by_name ]
    end
  end

  def linkable_ref?(ref)
    !ref.start_with?("documentation/roe/")
  end

  # An absolute path under site/ → relative, or nil. File paths are stored
  # as realpaths, which can differ from SITE_PATH (a symlinked folder).
  def relative(path)
    roots.each do |root|
      return path.delete_prefix(root) if path.start_with?(root)
    end
    nil
  end

  def roots
    @roots ||= [ RoeSitePaths::SITE_PATH.to_s, (File.realpath(RoeSitePaths::SITE_PATH.to_s) rescue nil) ]
               .compact.uniq.map { |r| r.end_with?("/") ? r : "#{r}/" }
  end
end
