class Page < ApplicationRecord
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

    # Find or create page - with duplicate handling
    existing_pages = where(file_path: absolute_path)

    if existing_pages.count > 1
      # Cleanup duplicates: keep newest, delete rest
      Rails.logger.warn "Found #{existing_pages.count} pages for #{file_path}, cleaning up duplicates"
      page = existing_pages.order(created_at: :desc).first
      existing_pages.where.not(id: page.id).destroy_all
      puts "  ℹ Removed #{existing_pages.count - 1} duplicate(s) for #{File.basename(file_path)}"
    else
      page = existing_pages.first_or_initialize
    end

    if parsed.front_matter["tags"].is_a?(String)
      parsed.front_matter["tags"] = parsed.front_matter["tags"]
        .split(",")
        .map(&:strip)
        .reject(&:blank?)
    end

    # Store ALL frontmatter in metadata JSON
    page.metadata = parsed.front_matter
    page.content = parsed.content

    # Save with error handling
    begin
      page.save!
    rescue => e
      Rails.logger.error "Failed to save #{file_path}: #{e.message}"
      puts "\n  ✗ Error saving: #{File.basename(file_path)} - #{e.message}\n"
      return nil
    end

    page
  end

  def self.remove_by_file_path(file_path)
    absolute_path = RoeSitePaths.normalize(file_path)
    find_by(file_path: absolute_path)&.destroy
  end

  def self.public_pages
    where("json_extract(metadata, '$.status') = ?", "published")
  end

  def filename
    File.basename(file_path, ".md") if file_path.present?
  end

  # True for pages stored under site/pages/members/ — used by the public
  # page view to add a `member-page` CSS class so theme styles can target
  # signup / signin / upgrade / donate / etc. distinctly from regular pages.
  def member_page?
    file_path.to_s.include?("/site/pages/members/")
  end

  # Metadata fields that point at files under site/media/...
  MEDIA_FIELDS = %w[image].freeze

  # Returns names of site-gated metadata fields that are blank but should
  # be set on a published page. Pages support paid audience but never
  # newsletter delivery, so we only check audience here.
  def missing_site_gated_fields
    return [] unless SiteFeature.memberships_enabled?
    metadata["audience"].to_s.strip.blank? ? [ "audience" ] : []
  end

  def media_refs
    MEDIA_FIELDS.filter_map do |field|
      path = metadata[field].to_s.strip
      next if path.empty?

      exists = if path.start_with?("/media/")
                 Post.media_file_set.include?(path)
      else
                 true
      end
      { field: field, path: path, exists: exists }
    end
  end

  def missing_media_refs
    media_refs.reject { |ref| ref[:exists] }
  end

  # A published page "needs attention" if its audience field is blank
  # (when paid memberships are enabled) or its image references a file
  # that doesn't exist on disk.
  def needs_attention?
    return false unless published?
    missing_site_gated_fields.any? || missing_media_refs.any?
  end

  private

  # def to_html
  #   Kramdown::Document.new(
  #     content,
  #     footnote_backlink: '↩'
  #   ).to_html
  # end
end
