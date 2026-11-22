# Keeps links between the site's own content working when an item moves.
#
#   file_renamed("posts/old", "posts/new")
#     [[posts/old]], [[old]] (when no other file is called that) and
#     [text](/posts/old.md) → the new file name.
#
#   address_changed("/posts/old", "/posts/new")
#     [text](/posts/old) and href="/posts/old" → the new address: old links
#     written as addresses, from before links to files.
#
#   names_changed(source, record)
#     The places that name an item rather than link to it: `post:` and
#     `product:` in a card, `order:` in a collection (menus too), and
#     `related:` in front matter. A file name there follows a file rename;
#     a url_name follows a url_name change, unless the old url_name still
#     belongs to something else (a page and a post can share one).
#
# Looks in posts, pages, products, the site's own docs and the layout files
# (header, footer, sidebar). Code is left alone, both fenced and inline. Each
# changed file is re-read into its record. Returns the number of links
# changed.
#
# Runs whenever Roe sees an item move: a save or rename in the admin (which
# says how many links it updated), a file changed outside Roe while it runs
# (ContentWatcher), and changes made while it wasn't running, at the sync
# when it starts (ContentSync#follow_links). Broken links are the worse
# surprise.
#
# The redirect a rename can add (RenameRedirect) is separate: it's for
# visitors arriving from outside — bookmarks, search engines, other sites.
class InternalLinkRewriter
  CONTENT_MODELS = %w[Post Page Product Documentation].freeze

  # Where links to a record point now: its file name and its address. Take
  # it before a save or rename, then hand it to .follow after.
  def self.source_for(record)
    { ref: InternalLinks.ref_for(record), address: record.public_url, url_name: record.url_name.to_s }
  end

  # Points links at the record's new file name and address, if either moved.
  # `except`: a file to leave alone (the record's own, whose text an editor
  # may hold). Returns the number of links changed.
  def self.follow(source, record, except: nil)
    return 0 unless source && record

    file_renamed(source[:ref], InternalLinks.ref_for(record), except: except) +
      address_changed(source[:address], record.public_url, except: except) +
      names_changed(source, record, except: except)
  end

  NAMING_KEYS = { "card" => %w[post product], "collection" => %w[order] }.freeze

  def self.names_changed(source, record, except: nil)
    old_ref = source[:ref].to_s.delete_prefix("/")
    new_ref = InternalLinks.ref_for(record).to_s
    old_name = source[:url_name].to_s
    new_name = record.url_name.to_s
    file_moved = old_ref.present? && new_ref.present? && old_ref != new_ref
    name_moved = old_name.present? && new_name.present? && old_name != new_name && !url_name_taken?(old_name)
    return 0 unless file_moved || name_moved

    # A folderless `old.md` meant this file only if no other file is called that.
    base = File.basename(old_ref)
    bare = file_moved && InternalLinks.index.last.fetch(base, []).none? { |item| ![ old_ref, new_ref ].include?(item.ref) }

    links = 0
    swap = lambda do |value|
      replaced = if file_moved && InternalLinks.file_name?(value)
        ref = InternalLinks.split(value).first
        if ref.casecmp?(old_ref) || (bare && ref.casecmp?(base))
          "#{'/' if value.start_with?('/')}#{new_ref}#{'.md' if value.match?(/\.md\z/i)}"
        end
      elsif name_moved && (named = value.match(%r{\A(/(?:posts|pages|store|documentation)/|/)?(.+)\z})) && named[2].casecmp?(old_name)
        # A card's `post:` may carry the address prefix: `/posts/old-name`.
        "#{named[1]}#{new_name}"
      end
      next value unless replaced

      links += 1
      replaced
    end

    new(except: except).rewrite(raw: true) { |text| swap_names(text, swap) }
    links
  end

  # Is a url_name in use by any item? (Roe's own docs aside.)
  def self.url_name_taken?(name)
    CONTENT_MODELS.any? do |model|
      scope = model.constantize.where("json_extract(metadata, '$.url_name') = ?", name)
      scope = scope.where("file_path NOT LIKE '%/documentation/roe/%'") if model == "Documentation"
      scope.exists?
    end
  end

  # Runs `swap` over every value that names an item, leaving the rest of the
  # text exactly as it was.
  def self.swap_names(text, swap)
    front = text.start_with?("---") ? :open : nil
    related = false
    fence = nil
    keys = nil

    text.lines.each_with_index.map do |line, i|
      if front == :open && i.positive?
        if line.strip == "---"
          front = :done
          next line
        end
        if (m = line.match(/\A(related:[ \t]*)(.*?)(\s*)\z/m))
          related = m[2].empty?
          next related ? line : "#{m[1]}#{swap_list(m[2], swap)}#{m[3]}"
        end
        if related && (m = line.match(/\A(\s*-[ \t]*)(.*?)(\s*)\z/m))
          next "#{m[1]}#{swap_value(m[2], swap)}#{m[3]}"
        end
        related = false unless line.strip.empty?
        next line
      end
      next line if front == :open

      if (open = line.match(/\A {0,3}(`{3,}|~{3,})[ \t]*([\w-]*)/))
        if fence.nil?
          fence = open[1]
          keys = NAMING_KEYS[open[2].downcase]
          next line
        elsif open[1][0] == fence[0] && open[1].length >= fence.length && line.strip == open[1]
          fence = nil
          keys = nil
          next line
        end
      end
      next line unless keys

      m = line.match(/\A(\s*(\w+):[ \t]*)(.*?)(\s*)\z/m)
      next line unless m && keys.include?(m[2])

      "#{m[1]}#{swap_list(m[3], swap)}#{m[4]}"
    end.join
  end

  # A comma-separated list, a [bracketed] one, or a single value. Inline
  # Markdown links (a menu's `[Feed](/feed.xml)`) are left as they are.
  def self.swap_list(value, swap)
    inner = value.match(/\A\[(.*)\]\z/m)
    return "[#{swap_list(inner[1], swap)}]" if inner && !value.match?(/\A\[[^\]]*\]\(/)

    value.scan(/\[[^\]]*\]\([^)]*\)|[^,]+|,/).map do |part|
      part == "," || part.lstrip.start_with?("[") ? part : swap_value(part, swap)
    end.join
  end

  # One value, keeping its spacing and quotes.
  def self.swap_value(part, swap)
    m = part.match(/\A(\s*)(["']?)(.*?)\2(\s*)\z/m)
    return part unless m && m[3].present?

    replaced = swap.call(m[3])
    replaced == m[3] ? part : "#{m[1]}#{m[2]}#{replaced}#{m[2]}#{m[4]}"
  end

  def self.file_renamed(old_ref, new_ref, except: nil)
    old_ref = old_ref.to_s.delete_prefix("/")
    new_ref = new_ref.to_s.delete_prefix("/")
    return 0 if old_ref.blank? || new_ref.blank? || old_ref == new_ref

    name = File.basename(old_ref)
    # A bare [[name]] meant this file only if no other file is called that.
    bare = InternalLinks.index.last.fetch(name, []).none? { |item| ![ old_ref, new_ref ].include?(item.ref) }
    targets = [ Regexp.escape(old_ref) ]
    targets << Regexp.escape(name) if bare
    wiki = /\[\[(\s*)\/?(?:#{targets.join('|')})(?:\.md)?(\s*(?:#[^\[\]|\n]*)?(?:\|[^\[\]\n]*)?)\]\]/
    md = %r{\]\(\s*/?#{Regexp.escape(old_ref)}\.md((?:#[^)\s]*)?(?:\s+"[^"]*")?\s*)\)}

    links = 0
    new(except: except).rewrite do |text|
      text.gsub(wiki) { links += 1; "[[#{Regexp.last_match(1)}#{new_ref}#{Regexp.last_match(2)}]]" }
          .gsub(md) { links += 1; "](/#{new_ref}.md#{Regexp.last_match(1)})" }
    end
    links
  end

  def self.address_changed(old_address, new_address, except: nil)
    old_address = old_address.to_s
    new_address = new_address.to_s
    return 0 if old_address.blank? || new_address.blank? || old_address == new_address || old_address == "/"

    md = %r{\]\(\s*#{Regexp.escape(old_address)}((?:#[^)\s]*)?(?:\s+"[^"]*")?\s*)\)}
    href = /href=(["'])#{Regexp.escape(old_address)}(#[^"']*)?\1/

    links = 0
    new(except: except).rewrite do |text|
      text.gsub(md) { links += 1; "](#{new_address}#{Regexp.last_match(1)})" }
          .gsub(href) { links += 1; "href=#{Regexp.last_match(1)}#{new_address}#{Regexp.last_match(2)}#{Regexp.last_match(1)}" }
    end
    links
  end

  def initialize(except: nil)
    @except = except && File.expand_path(except.to_s)
  end

  # Runs the block over the text of every file, outside code, and writes the
  # files it changed. `raw`: the whole text, code blocks and all, for
  # changes that look inside them (names_changed).
  def rewrite(raw: false, &change)
    count = 0
    each_file do |path, model|
      next if @except && File.expand_path(path) == @except

      original = File.read(path)
      updated = raw ? change.call(original) : outside_code(original, &change)
      next if updated == original

      File.write(path, updated)
      resync(path, model)
      count += 1
    end
    count
  end

  private

  def each_file
    CONTENT_MODELS.each do |name|
      model = name.constantize
      model.select(:id, :file_path).find_each do |record|
        path = record.file_path.to_s
        path = File.join(RoeSitePaths::SITE_PATH, path) unless path.start_with?("/")
        ref = InternalLinks.ref_for(record)
        next if ref.nil? || !InternalLinks.linkable_ref?(ref) || !File.file?(path)

        yield path, model
      end
    end
    Dir.glob(File.join(RoeSitePaths::SITE_PATH, "layout", "*.md")).each { |path| yield path, nil }
  end

  # Fenced code blocks and `inline code` pass through untouched.
  def outside_code(text)
    fence = nil
    text.lines.map do |line|
      if (open = line.match(/\A {0,3}(`{3,}|~{3,})/))
        marker = open[1]
        if fence.nil?
          fence = marker
          next line
        elsif marker[0] == fence[0] && marker.length >= fence.length && line.strip == marker
          fence = nil
          next line
        end
      end
      next line if fence

      line.split(/(`+[^`]*`+)/).map.with_index { |part, i| i.odd? ? part : yield(part) }.join
    end.join
  end

  # Layout files (model nil) are read from disk when a page is drawn.
  def resync(path, model)
    if model == Documentation
      Documentation.create_or_update_from_file(path)
    elsif model
      ContentSync.sync_file(path)
    end
  end
end
