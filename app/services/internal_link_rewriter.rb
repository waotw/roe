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
# Looks in posts, pages, products, the site's own docs and the layout files
# (header, footer, sidebar). Code is left alone, both fenced and inline. Each
# changed file is re-read into its record. Returns the number of files
# changed.
#
# The redirect a rename can add (RenameRedirect) is separate: it's for
# visitors arriving from outside — bookmarks, search engines, other sites.
class InternalLinkRewriter
  CONTENT_MODELS = %w[Post Page Product Documentation].freeze

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

    new(except: except).rewrite do |text|
      text.gsub(wiki) { "[[#{Regexp.last_match(1)}#{new_ref}#{Regexp.last_match(2)}]]" }
          .gsub(md) { "](/#{new_ref}.md#{Regexp.last_match(1)})" }
    end
  end

  def self.address_changed(old_address, new_address, except: nil)
    old_address = old_address.to_s
    new_address = new_address.to_s
    return 0 if old_address.blank? || new_address.blank? || old_address == new_address || old_address == "/"

    md = %r{\]\(\s*#{Regexp.escape(old_address)}((?:#[^)\s]*)?(?:\s+"[^"]*")?\s*)\)}
    href = /href=(["'])#{Regexp.escape(old_address)}(#[^"']*)?\1/

    new(except: except).rewrite do |text|
      text.gsub(md) { "](#{new_address}#{Regexp.last_match(1)})" }
          .gsub(href) { "href=#{Regexp.last_match(1)}#{new_address}#{Regexp.last_match(2)}#{Regexp.last_match(1)}" }
    end
  end

  def initialize(except: nil)
    @except = except && File.expand_path(except.to_s)
  end

  # Runs the block over the text of every file, outside code, and writes the
  # files it changed.
  def rewrite(&change)
    count = 0
    each_file do |path, model|
      next if @except && File.expand_path(path) == @except

      original = File.read(path)
      updated = outside_code(original, &change)
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
