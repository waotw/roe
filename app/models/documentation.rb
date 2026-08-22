class Documentation < ApplicationRecord
  self.table_name = "documentation"

  include HasAudience
  include HasMetadata
  include HasMarkdownExtensions
  include HasInlineFootnotes
  include TouchesMediaUsageIndex

  def self.create_or_update_from_file(file_path)
    # Resolve symlinks (notably /rails/site → /data/site on prod) so
    # this lookup matches records created via other paths into this
    # model. See RoeSitePaths.normalize for the why.
    absolute_path = RoeSitePaths.normalize(file_path)

    # Parse with error handling
    begin
      parsed = FrontMatterParser::Parser.parse_file(file_path)
    rescue => e
      Rails.logger.error "Failed to parse #{file_path}: #{e.message}"
      puts "\n  ✗ Error parsing: #{File.basename(file_path)} - #{e.message}\n"
      return nil
    end

    # Find or create documentation - with duplicate handling
    existing_docs = where(file_path: absolute_path)

    if existing_docs.count > 1
      # Cleanup duplicates: keep newest, delete rest
      Rails.logger.warn "Found #{existing_docs.count} docs for #{file_path}, cleaning up duplicates"
      doc = existing_docs.order(created_at: :desc).first
      existing_docs.where.not(id: doc.id).destroy_all
      puts "  ℹ Removed #{existing_docs.count - 1} duplicate(s) for #{File.basename(file_path)}"
    else
      doc = existing_docs.first_or_initialize(file_path: absolute_path)
    end

    if parsed.front_matter["tags"].is_a?(String)
      parsed.front_matter["tags"] = parsed.front_matter["tags"]
        .split(",")
        .map(&:strip)
        .reject(&:blank?)
    end

    # Store ALL frontmatter in metadata JSON
    doc.metadata = parsed.front_matter
    doc.content = parsed.content

    # Save with error handling
    begin
      doc.save!
    rescue => e
      Rails.logger.error "Failed to save #{file_path}: #{e.message}"
      puts "\n  ✗ Error saving: #{File.basename(file_path)} - #{e.message}\n"
      return nil
    end

    doc
  end

  def self.remove_by_file_path(file_path)
    absolute_path = RoeSitePaths.normalize(file_path)
    find_by(file_path: absolute_path)&.destroy
  end

  def self.public_documentation
    where("json_extract(metadata, '$.status') = ?", "published")
  end

  # Docs directly inside site/documentation (not in any subdirectory).
  def self.root
    where("file_path NOT LIKE ?", "#{normalized_documentation_path}/%/%")
  end

  # Scope to docs inside a subdirectory of site/documentation.
  # dir should be a relative path like "roe" or "notes".
  # Blank dir scopes to root docs.
  def self.in_directory(dir)
    return root if dir.to_s.blank?

    base = File.join(normalized_documentation_path, dir.to_s, "")
    where("file_path LIKE ?", "#{base}%")
  end

  # The documentation path with symlinks resolved — must match what
  # ContentSync stored in the file_path column at sync time. On Fly,
  # /rails/site is a symlink to /data/site (the persistent volume),
  # and ContentSync calls RoeSitePaths.normalize on every doc's path
  # before saving, so records end up with /data/site/... paths.
  # If this scope's LIKE pattern were built from the un-normalized
  # SITE_DOCUMENTATION_PATH constant, the prefix would be
  # /rails/site/... and would never match the stored paths → empty
  # collection on every query. Memoized so we don't realpath() per
  # query; the path doesn't change during the process's lifetime.
  # Only remembered once the directory is really there.
  #
  # RoeSitePaths.normalize falls back to the un-resolved path when realpath
  # can't find it. Caching that is unrecoverable: on Fly the prefix would stay
  # /rails/site/documentation for the life of the process while ContentSync
  # writes /data/site/documentation, so every LIKE matches nothing and the
  # collection is empty until a restart happens to catch a better moment.
  #
  # site/documentation is missing more often than you'd think — before a first
  # Site Sync brings it across, and in the window around an update.
  def self.normalized_documentation_path
    return @normalized_documentation_path if @normalized_documentation_path

    path = RoeSitePaths::SITE_DOCUMENTATION_PATH
    resolved = RoeSitePaths.normalize(path)
    @normalized_documentation_path = resolved if Dir.exist?(path)
    resolved
  end

  # Return all unique tags across documentation records, optionally scoped
  # to a subdirectory. Blank dir scopes to root docs.
  def self.all_tags(dir = nil)
    scope = case dir
    when nil then all
    when "" then root
    else in_directory(dir)
    end
    scope.to_a.flat_map(&:tags).uniq.sort
  end

  # Public URL, mirroring the doc's directory under site/documentation.
  # A doc inside a subdirectory is namespaced by its top-level folder
  # (site/documentation/roe/... → /documentation/roe/<url_name>), so Roe's
  # bundled docs never collide with a user's own docs at
  # /documentation/<url_name>. Docs in the documentation root stay flat.
  # Deeper nesting (roe/tutorials/...) collapses to the top-level scope;
  # url_name is unique within a scope.
  def public_url
    scope = url_scope
    scope.present? ? "/documentation/#{scope}/#{url_name}" : "/documentation/#{url_name}"
  end

  # Top-level subdirectory under site/documentation this doc lives in
  # (e.g. "roe"), or nil for docs directly in the documentation root.
  def url_scope
    root = self.class.normalized_documentation_path
    rel  = file_path.to_s.sub(/\A#{Regexp.escape(root)}\/?/, "")
    segments = rel.split("/")
    segments.length > 1 ? segments.first.presence : nil
  end

  # Roe ships its own documentation under documentation/roe. On a user's site
  # that's noise, so it's excluded from BOTH search and the static build by
  # default; `search_roe_docs: true` opts it back in. One rule, two consumers
  # (SearchIndexGenerator and StaticGenerator) — so "excluded from search"
  # always means "not published to the static site."
  def self.include_roe_docs?
    value = SiteConfig.content("search.roe_docs")
    value == true || value == "true"
  end

  # Published docs that should be exposed — to search and to the static site.
  def self.publishable
    return published if include_roe_docs?
    published.where("file_path NOT LIKE ?", "%/documentation/roe/%")
  end

  # Should this doc be published (to search / the static site)? Roe's bundled
  # docs (documentation/roe) are gated behind include_roe_docs?.
  def publishable?
    return true unless url_scope == "roe"
    self.class.include_roe_docs?
  end
end
