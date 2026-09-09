require "time"

# Orchestrates a Files import: walk the extracted tree, parse + classify each
# content file, copy its bundled media, and write it as a draft post or page
# through the shared ContentWriter. Dedupes on the source path so re-running a
# ZIP skips what's already in.
class FilesImporter::Runner
  Result = Struct.new(:posts, :pages, :skipped, :assets, :ambiguous, :warnings, keyword_init: true)

  IGNORE_DIRS = %w[.git node_modules .well-known __MACOSX].freeze

  # overrides: { "source/path.md" => "post" | "page" | "skip" } from the review
  # step, taking precedence over the classifier.
  # media_mode: :referenced (default) copies only media a doc references;
  # :all also copies every other media file bundled in the ZIP/folder.
  def initialize(root:, overrides: {}, import_ref: nil, media_mode: :referenced,
                 posts_dir: RoeSitePaths::SITE_POSTS_PATH,
                 pages_dir: RoeSitePaths::SITE_PAGES_PATH,
                 media_root: File.join(RoeSitePaths::SITE_PATH, "media"))
    @root       = effective_root(File.expand_path(root))
    @overrides  = (overrides || {}).transform_values(&:to_s)
    @import_ref = import_ref
    @media_mode = media_mode.to_sym
    @parser     = FilesImporter::Parser.new
    @writer     = ContentWriter.new(posts_dir: posts_dir, pages_dir: pages_dir)
    @copier     = FilesImporter::MediaCopier.new(root: @root, media_root: media_root)
  end

  # Parse + classify every content file without writing — powers the preview /
  # review screen.
  def documents
    content_files.map do |abs, rel|
      doc = @parser.parse(abs, rel)
      doc.kind = FilesImporter::Classifier.classify(doc)
      doc
    end
  end

  def import
    result = Result.new(posts: 0, pages: 0, skipped: 0, assets: [], ambiguous: [], warnings: [])
    content_files.each do |abs, rel|
      doc = @parser.parse(abs, rel)
      kind = resolved_kind(doc, rel)
      next if kind == :skip

      if already_imported?(rel)
        result.skipped += 1
        next
      end

      metadata, meta_assets = @copier.rewrite_metadata(metadata_for(doc, kind), rel)
      body, body_assets = @copier.rewrite(doc.body, rel)
      result.assets.concat(meta_assets).concat(body_assets)

      target = (kind == :page ? :page : :post)
      @writer.write(kind: target, filename: doc.basename, metadata: metadata, body: body)

      target == :page ? result.pages += 1 : result.posts += 1
      result.ambiguous << rel if kind == :ambiguous
    rescue => e
      result.warnings << "#{rel}: #{e.class} #{e.message}"
      Rails.logger.error "[FilesImporter] #{rel}: #{e.class} #{e.message}"
    end

    # "Import all media" — sweep in any bundled files nothing referenced.
    result.assets.concat(@copier.copy_unreferenced) if @media_mode == :all
    result
  end

  private

  # A ZIP made from a folder unwraps to a single top-level directory (often
  # alongside __MACOSX / dotfiles). Descend into that wrapper so root-absolute
  # asset paths (/images/x) resolve and top-level files classify as pages.
  # Don't descend into a real content folder (posts/, _posts/, pages/) — that
  # would change how its files classify.
  def effective_root(dir)
    entries = Dir.children(dir).reject { |e| e.start_with?(".") || IGNORE_DIRS.include?(e) }
    return dir unless entries.size == 1

    only = entries.first
    full = File.join(dir, only)
    return dir unless File.directory?(full)

    content_folder = (FilesImporter::Classifier::POST_DIRS + FilesImporter::Classifier::PAGE_DIRS).include?(only.downcase)
    content_folder ? dir : effective_root(full)
  end

  def resolved_kind(doc, rel)
    case @overrides[rel]
    when "post" then :post
    when "page" then :page
    when "skip" then :skip
    else FilesImporter::Classifier.classify(doc)
    end
  end

  # Ambiguous files still import (as posts) so nothing is silently dropped; the
  # review step is where a user can redirect or skip them.
  def metadata_for(doc, kind)
    page = (kind == :page)
    meta = {
      "title"       => doc.title,
      "date"        => normalize_date(doc.date),
      "status"      => "draft",
      "post_type"   => (page ? nil : "article"),
      "tags"        => doc.tags.presence,
      "author"      => doc.author,
      "subtitle"    => doc.subtitle,
      "excerpt"     => doc.excerpt,
      "source_file" => doc.source_path,
      "import_ref"  => @import_ref
    }
    meta["url_name"] = doc.slug if doc.slug.present?
    meta.compact.merge(stringify_custom(doc.custom))
  end

  # Keep unmapped frontmatter, but only scalar/simple values the YAML writer
  # can round-trip; anything nested is dropped from frontmatter (it stays in
  # the original file we don't delete).
  def stringify_custom(custom)
    (custom || {}).each_with_object({}) do |(k, v), h|
      next if v.is_a?(Hash)
      h[k.to_s] = v.is_a?(Array) ? v.map(&:to_s) : v
    end
  end

  def normalize_date(raw)
    return nil if raw.blank?
    Time.parse(raw.to_s).utc.iso8601
  rescue ArgumentError
    nil
  end

  # Deduped on the stored source path, across both posts and pages.
  def already_imported?(rel)
    Post.exists?([ "json_extract(metadata, '$.source_file') = ?", rel ]) ||
      Page.exists?([ "json_extract(metadata, '$.source_file') = ?", rel ])
  end

  def content_files
    Dir.glob(File.join(@root, "**", "*"), File::FNM_DOTMATCH)
       .reject { |p| (p.split(File::SEPARATOR) & IGNORE_DIRS).any? }
       .select { |p| File.file?(p) && FilesImporter::Parser.content_file?(p) }
       .map { |abs| [ abs, relative(abs) ] }
       .sort_by { |_, rel| rel }
  end

  def relative(abs)
    Pathname.new(File.expand_path(abs)).relative_path_from(Pathname.new(@root)).to_s
  end
end
