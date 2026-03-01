class Post < ApplicationRecord
  def self.create_or_update_from_file(file_path)
    absolute_path = File.expand_path(file_path)
    has_warnings = false

    # Parse with error handling
    begin
      parsed = FrontMatterParser::Parser.parse_file(file_path)
    rescue => e
      Rails.logger.error "Failed to parse #{file_path}: #{e.message}"
      puts "\n  ✗ Error parsing: #{File.basename(file_path)} - #{e.message}\n"
      return nil
    end

    # Validate date if present
    if parsed.front_matter['date'].present?
      begin
        Date.parse(parsed.front_matter['date'].to_s)
      rescue ArgumentError, TypeError => e
        Rails.logger.error "Invalid date in #{file_path}: #{parsed.front_matter['date']}"
        puts "\n  ✗ Invalid date: #{File.basename(file_path)} - '#{parsed.front_matter['date']}' is not a valid date\n"
        return nil
      end
    end

    # Check for required fields if published
    if parsed.front_matter['status'] == 'published'
      if parsed.front_matter['title'].blank?
        Rails.logger.warn "Published post missing title: #{file_path}"
        puts "\n  ⚠ Missing title: #{File.basename(file_path)}"
        has_warnings = true
      end

      if parsed.front_matter['date'].blank?
        Rails.logger.warn "Published post missing date: #{file_path}"
        puts "  ⚠ Missing date: #{File.basename(file_path)}\n"
        has_warnings = true
      end
    end

    # Find or create post
    post = find_or_initialize_by(file_path: absolute_path)

    # Store ALL frontmatter in metadata JSON
    post.metadata = parsed.front_matter
    post.content = parsed.content

    # Save with error handling
    begin
      post.save!
    rescue => e
      Rails.logger.error "Failed to save #{file_path}: #{e.message}"
      puts "\n  ✗ Error saving: #{File.basename(file_path)} - #{e.message}\n"
      return nil
    end

    # Return warning status if there were warnings, otherwise return post
    has_warnings ? :warning : post
  end

  def self.remove_by_file_path(file_path)
    absolute_path = File.expand_path(file_path)
    find_by(file_path: absolute_path)&.destroy
  end

  def to_html
    Kramdown::Document.new(
      content,
      footnote_backlink: '↩'
    ).to_html
  end

  def validate_for_display
    errors = []

    if published?
      errors << "Published posts must have a title" if metadata["title"].blank?
      errors << "Published posts must have a date" if metadata["date"].blank?
    end

    errors
  end

  # Convenience methods for common fields
  def title
    metadata["title"]
  end

  def subtitle
    metadata["subtitle"]
  end

  def url_name
    # Generate from filename if not in metadata
    metadata["url_name"] || File.basename(file_path, '.md')
  end

  def date
    # Handle both Date objects and strings
    date_value = metadata["date"]

    return nil if date_value.blank?

    # If it's already a Date object, return it
    return date_value if date_value.is_a?(Date)

    # Try to parse string
    begin
      Date.parse(date_value.to_s)
    rescue ArgumentError, TypeError
      # If parsing fails, use file modification time as fallback
      File.mtime(file_path).to_date
    end
  end

  def author
    metadata["author"]
  end

  # Status methods
  def status
    metadata["status"] || "draft"
  end

  def published?
    status == "published"
  end

  def draft?
    status == "draft"
  end

  # Type methods
  def self.types
    pluck(Arel.sql("DISTINCT json_extract(metadata, '$.type')"))
      .compact
      .sort
  end

  def self.by_type(type)
    where("json_extract(metadata, '$.type') = ?", type)
  end

  def type
    metadata["type"] || "article"
  end

  # Class methods for filtering by type
  def self.articles
    where("json_extract(metadata, '$.type') = ?", "article")
  end

  def self.music
    where("json_extract(metadata, '$.type') = ?", "music")
  end

  def self.podcasts
    where("json_extract(metadata, '$.type') = ?", "podcast")
  end

  def self.images
    where("json_extract(metadata, '$.type') = ?", "image")
  end

  # Class methods for filtering by status
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
