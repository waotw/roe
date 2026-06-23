class Documentation < ApplicationRecord
  self.table_name = "documentation"

  include HasAudience
  include HasMetadata
  include HasMarkdownExtensions
  include HasInlineFootnotes

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
    where("file_path NOT LIKE ?", "#{RoeSitePaths::SITE_DOCUMENTATION_PATH}/%/%")
  end

  # Scope to docs inside a subdirectory of site/documentation.
  # dir should be a relative path like "roe" or "notes".
  # Blank dir scopes to root docs.
  def self.in_directory(dir)
    return root if dir.to_s.blank?

    base = File.join(RoeSitePaths::SITE_DOCUMENTATION_PATH, dir.to_s, "")
    where("file_path LIKE ?", "#{base}%")
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
end
