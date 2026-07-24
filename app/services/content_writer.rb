# The shared tail end of every importer: take a mapped document (frontmatter
# hash + markdown body) and land it as a real Roe post or page — write the
# file, then sync the DB record. It guarantees it never overwrites an existing
# file (appends -2, -3, …) and keeps `url_name` in step with the final
# filename. Dedup/skip decisions stay with the caller (each source has its own
# identity rules); this only writes.
#
# posts_dir/pages_dir are overridable so tests can target a temp directory.
class ContentWriter
  def initialize(posts_dir: RoeSitePaths::SITE_POSTS_PATH, pages_dir: RoeSitePaths::SITE_PAGES_PATH)
    @dirs = { post: posts_dir, page: pages_dir }
  end

  # kind:     :post | :page
  # metadata: frontmatter hash
  # body:     markdown string
  # filename: desired file basename; defaults to metadata["url_name"]. Lets the
  #           Files importer preserve a source filename while carrying a
  #           distinct explicit url_name (slug/permalink).
  # Returns the final basename written (with any -N disambiguation applied).
  def write(kind:, metadata:, body:, filename: nil)
    model = model_for(kind)
    dir   = @dirs.fetch(kind)
    FileUtils.mkdir_p(dir)

    base   = (filename.presence || metadata["url_name"]).to_s.strip.presence || "item"
    actual = unique_slug(dir, base)

    # Keep url_name in step with the file only when the caller didn't set an
    # explicit, distinct one — otherwise a -N-suffixed filename would silently
    # diverge from a url_name Roe derives from the filename.
    metadata = metadata.dup
    if metadata["url_name"].blank? || metadata["url_name"].to_s == base
      metadata["url_name"] = actual
    end

    path = File.join(dir, "#{actual}.md")
    File.write(path, "---\n#{model.format_metadata_yaml(metadata)}\n---\n#{body}\n")
    model.create_or_update_from_file(path)
    actual
  end

  private

  def model_for(kind)
    case kind
    when :post then Post
    when :page then Page
    else raise ArgumentError, "kind must be :post or :page, got #{kind.inspect}"
    end
  end

  # Never overwrite an existing file: if <slug>.md is taken, append -2, -3, …
  def unique_slug(dir, slug)
    slug = slug.to_s.presence || "item"
    return slug unless File.exist?(File.join(dir, "#{slug}.md"))
    n = 2
    n += 1 while File.exist?(File.join(dir, "#{slug}-#{n}.md"))
    "#{slug}-#{n}"
  end
end
