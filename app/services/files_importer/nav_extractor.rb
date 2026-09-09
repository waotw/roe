# Finds the site's primary <nav> in an imported set of HTML files. A full HTML
# site repeats the same nav on every page, so we collect every <nav>'s link
# set, dedupe identical ones, prefer the home/index page, and return the most
# common one. Each nav's descendant <a href> links are collected (ignoring the
# structural noise), so both a simple <ul> nav and a deeply-nested one work.
class FilesImporter::NavExtractor
  Nav = Struct.new(:links, :sources, keyword_init: true)

  def self.extract(root)
    new(root).extract
  end

  def initialize(root)
    @root = File.expand_path(root)
  end

  # The primary nav (links + the files it appeared in), or nil when none found.
  def extract
    tally = {}
    html_files.each do |path|
      rel = relative(path)
      link_sets(path).each do |links|
        next if links.empty?
        key = links.map { |l| "#{l[:text]}|#{l[:href]}" }.join("\n")
        entry = (tally[key] ||= { links: links, sources: [], score: 0 })
        entry[:sources] << rel
        entry[:score] += index_like?(rel) ? 100 : 1
      end
    end
    return nil if tally.empty?

    best = tally.values.max_by { |e| e[:score] }
    Nav.new(links: best[:links], sources: best[:sources].uniq)
  end

  private

  def html_files
    Dir.glob(File.join(@root, "**", "*"), File::FNM_DOTMATCH)
       .select { |p| File.file?(p) && %w[.html .htm].include?(File.extname(p).downcase) }
  end

  def link_sets(path)
    Nokogiri::HTML(File.read(path)).css("nav").map do |nav|
      nav.css("a[href]").filter_map do |a|
        text = a.text.strip.gsub(/\s+/, " ")
        href = a["href"].to_s.strip
        next if text.empty? || href.empty? || href.start_with?("#", "javascript:")
        { text: text, href: href }
      end
    end
  rescue StandardError
    []
  end

  def index_like?(rel)
    %w[index home default].include?(File.basename(rel, ".*").downcase)
  end

  def relative(path)
    Pathname.new(File.expand_path(path)).relative_path_from(Pathname.new(@root)).to_s
  end
end
