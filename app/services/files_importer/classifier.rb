# Decides whether a parsed Document is a post, a page, or genuinely ambiguous
# (which sends it to the manual review step). Signals, in priority order:
#   1. an explicit frontmatter layout/type hint
#   2. a posts-style folder (_posts, blog, articles, …)
#   3. a pages folder (_pages, pages)
#   4. a Jekyll dated filename (YYYY-MM-DD-title)
#   5. any real publish date → lean post
#   6. a top-level file with no date → lean page (about, contact, …)
#   7. otherwise ambiguous
class FilesImporter::Classifier
  POST_DIRS = %w[_posts posts post blog articles article news writing].freeze
  PAGE_DIRS = %w[_pages pages page].freeze
  JEKYLL_DATED = /\A\d{4}-\d{2}-\d{2}-/

  def self.classify(doc)
    new(doc).classify
  end

  def initialize(doc)
    @doc  = doc
    @dirs = File.dirname(doc.source_path).split("/").reject { |p| p.blank? || p == "." }.map(&:downcase)
  end

  def classify
    return @doc.type_hint.to_sym if %w[post page].include?(@doc.type_hint.to_s)
    return :post if (@dirs & POST_DIRS).any?
    return :page if (@dirs & PAGE_DIRS).any?
    return :post if @doc.basename.to_s.match?(JEKYLL_DATED)
    return :post if @doc.dated
    return :page if @dirs.empty?
    :ambiguous
  end
end
