class Page < ApplicationRecord
  include HasAudience
  include HasMetadata
  include HasMarkdownExtensions
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

    if parsed.front_matter['tags'].is_a?(String)
      parsed.front_matter['tags'] = parsed.front_matter['tags']
        .split(',')
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
    absolute_path = File.expand_path(file_path)
    find_by(file_path: absolute_path)&.destroy
  end

  def self.public_pages
    where("json_extract(metadata, '$.status') = ?", "published")
  end

  def filename
    File.basename(file_path, '.md') if file_path.present?
  end

  private

  # def to_html
  #   Kramdown::Document.new(
  #     content,
  #     footnote_backlink: '↩'
  #   ).to_html
  # end
end
