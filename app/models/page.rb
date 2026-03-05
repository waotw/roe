class Page < ApplicationRecord
  include HasCollections
  include HasInlineFootnotes

  def self.create_or_update_from_file(file_path)
    absolute_path = File.expand_path(file_path)

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
    absolute_path = File.expand_path(file_path)
    find_by(file_path: absolute_path)&.destroy
  end

  # def to_html
  #   Kramdown::Document.new(
  #     content,
  #     footnote_backlink: '↩'
  #   ).to_html
  # end

  # Convenience methods
  def title
    metadata["title"]
  end

  def status
    metadata["status"] || "draft" # Pages default to published
  end

  def url_name
    # Priority: explicit url_name > title > filename
    if metadata["url_name"].present?
      metadata["url_name"]
    elsif metadata["title"].present?
      metadata["title"].parameterize
    else
      File.basename(file_path, '.md')
    end
  end

  def published?
    status == "published"
  end

  def draft?
    status == "draft"
  end

  # Class methods for filtering
  def self.published
    where("json_extract(metadata, '$.status') = ?", "published")
  end

  def self.drafts
    where("json_extract(metadata, '$.status') = ?", "draft")
  end

  # Dynamic access to any metadata field
  def method_missing(method_name, *args, &block)
    if metadata.key?(method_name.to_s)
      metadata[method_name.to_s]
    else
      super
    end
  end

  def respond_to_missing?(method_name, include_private = false)
    metadata.key?(method_name.to_s) || super
  end
end
