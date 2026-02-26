class Post < ApplicationRecord
  def self.create_or_update_from_file(file_path)
    absolute_path = File.expand_path(file_path)
    parsed = FrontMatterParser::Parser.parse_file(file_path)
    filename = File.basename(file_path, '.md')

    post = find_or_initialize_by(file_path: absolute_path)

    # Store ALL frontmatter in metadata JSON
    post.metadata = parsed.front_matter
    post.content = parsed.content

    post.save!
    post
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
    date_value.is_a?(String) ? Date.parse(date_value) : date_value
  end

  def author
    metadata["author"]
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
