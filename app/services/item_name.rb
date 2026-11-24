# How Roe reads a name for an item, wherever one is written: a card's
# `post:`/`product:`, a collection's `order:`, `related:`, and a Markdown link
# that leaves off `.md`. One rule everywhere, so what works in one place works
# in the others:
#
#   home                 its url_name, or else its file name
#   home.md              its file
#   pages/home, /pages/home
#                        the same, among pages only — for when two kinds of
#                        item share a name
#   /pages/home.md       its file, in that folder
#
# `home` (or `pages/home`) also means the site's home page when no item has
# that url_name or file name, so `order: home` keeps working after the home
# page is renamed.
#
# A url_name wins over a file name: that's what every name written before
# file names meant, so old cards and orders keep meaning the same thing. When
# a short name could be two items, Roe uses the first and the Markdown check
# says so (`matches`). Adding the folder or `.md` settles it.
module ItemName
  # Folders as written, and the kind of item each holds. `store` is where
  # products live on the site, so `/store/x` reads as a product too.
  FOLDERS = {
    "posts" => "Post", "pages" => "Page", "products" => "Product",
    "store" => "Product", "documentation" => "Documentation"
  }.freeze
  MODELS = %w[Post Page Product Documentation].freeze

  Parsed = Struct.new(:folder, :name, :file, keyword_init: true) do
    # The site path a file of this name would have: posts/x, pages/x.
    def ref = folder ? "#{folder == 'store' ? 'products' : folder}/#{name}" : name
    def models = folder ? [ FOLDERS[folder] ] : MODELS
  end

  module_function

  def parse(value)
    text = value.to_s.strip.split("#", 2).first.to_s.strip
    file = text.match?(/\.md\z/i)
    text = text.sub(/\.md\z/i, "").delete_prefix("/")
    folder, rest = text.split("/", 2)
    return Parsed.new(folder: folder, name: rest, file: file) if rest.present? && FOLDERS.key?(folder)

    Parsed.new(folder: nil, name: text, file: file)
  end

  # The item a name means, from the database, or nil.
  def find(value)
    matches(value).first
  end

  # Every item a name could mean, the one Roe uses first. More than one means
  # the name is unclear.
  def matches(value)
    parsed = parse(value)
    return [] if parsed.name.blank?

    found = []
    found.concat(by_url_name(parsed)) unless parsed.file
    found.concat(by_file(parsed))
    found << Page.home if found.empty? && home_name?(parsed)
    found.compact.uniq
  end

  # Among `items` (a collection's), the one a name means: url_name first,
  # then file. nil when none.
  def pick(value, items)
    parsed = parse(value)
    return nil if parsed.name.blank?

    # Without a folder, anything with a url_name counts (a product group
    # stands in for its products in a grouped collection).
    pool = parsed.folder ? items.select { |item| parsed.models.include?(item.class.name) } : items
    name = parsed.name.downcase
    unless parsed.file
      hit = pool.find { |item| item.respond_to?(:url_name) && item.url_name.to_s.downcase == name }
      return hit if hit
    end
    pool.find { |item| file_matches?(item, parsed) } ||
      (home_name?(parsed) ? pool.find { |item| item.is_a?(Page) && item.home? } : nil)
  end

  def home_name?(parsed)
    parsed.name.to_s.downcase == "home" && !parsed.file && parsed.folder.in?([ nil, "pages" ])
  end

  def by_url_name(parsed)
    parsed.models.filter_map do |name|
      scope = name.constantize.where("json_extract(metadata, '$.url_name') = ?", parsed.name)
      scope = scope.where("file_path NOT LIKE '%/documentation/roe/%'") if name == "Documentation"
      scope.first
    end
  end

  def by_file(parsed)
    found = InternalLinks.lookup(parsed.ref)
    # Not Array(found): an Item is a Struct, which Array() would take apart.
    items = (found.is_a?(Array) ? found.map { |ref| InternalLinks.index.first[ref] } : [ found ]).compact
    items.select { |item| parsed.models.include?(item.model) }.filter_map(&:record)
  end

  def file_matches?(item, parsed)
    return false unless item.respond_to?(:file_path)

    ref = InternalLinks.ref_for(item).to_s.downcase
    return false if ref.empty?

    parsed.folder ? ref == parsed.ref.downcase : File.basename(ref) == parsed.name.downcase || ref == parsed.name.downcase
  end
end
