class Documentation < ApplicationRecord
  self.table_name = 'documentation'

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

    # Find or create documentation - with duplicate handling
    existing_docs = where(file_path: absolute_path)

    if existing_docs.count > 1
      # Cleanup duplicates: keep newest, delete rest
      Rails.logger.warn "Found #{existing_docs.count} docs for #{file_path}, cleaning up duplicates"
      doc = existing_docs.order(created_at: :desc).first
      existing_docs.where.not(id: doc.id).destroy_all
      puts "  ℹ Removed #{existing_docs.count - 1} duplicate(s) for #{File.basename(file_path)}"
    else
      doc = existing_docs.first_or_initialize
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
    absolute_path = File.expand_path(file_path)
    find_by(file_path: absolute_path)&.destroy
  end

  def self.public_documentation
    where("json_extract(metadata, '$.status') = ?", "published")
  end
end
