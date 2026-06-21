module HasMetadata
  extend ActiveSupport::Concern

  included do
    before_save :ensure_url_name_in_metadata

    # Status scopes
    scope :published, -> {
      where("json_extract(metadata, '$.status') = ?", "published")
    }

    scope :unlisted, -> {
      where("json_extract(metadata, '$.status') = ?", "unlisted")
    }

    scope :drafts, -> {
      where("json_extract(metadata, '$.status') = ?", "draft")
    }

    scope :not_draft, -> {
      where("json_extract(metadata, '$.status') != ?", "draft")
    }

    scope :public_items, -> {
      where("json_extract(metadata, '$.status') IN (?, ?)", "published", "unlisted")
    }

    # Tag scopes - optimized for JSON array searching
    scope :tagged_with, ->(tags) {
      tag_array = Array(tags)
      return none if tag_array.empty?

      # For SQLite JSON arrays, we need to check if the tag exists in the array
      # This uses LIKE but is more precise than before
      conditions = tag_array.map {
        # Match tag in array: ["tag"] or ["tag","other"] or ["other","tag"]
        "(json_extract(metadata, '$.tags') LIKE ? OR json_extract(metadata, '$.tags') LIKE ? OR json_extract(metadata, '$.tags') LIKE ?)"
      }

      params = tag_array.flat_map { |tag|
        [ "%\"#{tag}\"%", "%[\"#{tag}\"]%", "%,\"#{tag}\"%" ]
      }

      where(conditions.join(" OR "), *params)
    }

    scope :with_post_type, ->(type) {
      where("json_extract(metadata, '$.post_type') = ?", type)
    }

    # Date sorting
    scope :by_date, -> {
      order(Arel.sql("COALESCE(json_extract(metadata, '$.date'), created_at) DESC"))
    }

    scope :by_created, -> {
      order(created_at: :desc)
    }
  end

  class_methods do
    def format_metadata_yaml(metadata)
      # Extract guid to place at the end (and deduplicate if needed)
      guid_value = metadata.delete("guid")

      yaml_lines = []

      metadata.each do |key, value|
        yaml_lines << "#{key}: #{format_yaml_scalar(value)}"
      end

      # Add GUID at the end (if present)
      if guid_value.present?
        yaml_lines << "guid: #{format_yaml_scalar(guid_value)}"
      end

      yaml_lines.join("\n")
    end

    def format_yaml_scalar(value)
      case value
      when Numeric, TrueClass, FalseClass
        value.to_s
      when NilClass
        '""'
      when Array
        return "[]" if value.empty?
        "[#{value.map { |item| format_yaml_scalar(item) }.join(', ')}]"
      when String
        if value.empty?
          '""'
        elsif value.match?(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/)
          "\"#{value}\""
        else
          "\"#{value.gsub('"', '\"')}\""
        end
      else
        "\"#{value}\""
      end
    end
  end

  def raw_frontmatter
    full_path = File.join(RoeSitePaths::SITE_PATH, file_path)
    return "" unless File.exist?(full_path)

    content = File.read(full_path)

    # Extract everything between the --- delimiters
    if content =~ /\A---\s*\n(.*?)\n---\s*\n/m
      $1
    else
      ""
    end
  end

  def url_name
    metadata["url_name"] || calculate_url_name
  end

  def slug
    url_name
  end

  def title
    metadata["title"]
  end

  def subtitle
    metadata["subtitle"]
  end

  def image
    metadata["image"]
  end

  def excerpt
    metadata["excerpt"]
  end

  # Tags accessor - handle both string and array formats
  def tags
    tags_value = metadata["tags"]

    case tags_value
    when Array
      tags_value
    when String
      tags_value.split(",").map(&:strip)
    else
      []
    end
  end

  # Status methods.
  # Defaults to "draft" when not explicitly set — no-status content is
  # private until the author consciously publishes it. This is the safe
  # direction: it prevents accidental publication of in-progress work.
  def status
    metadata["status"].presence || "draft"
  end

  def published?
    status == "published"
  end

  def unlisted?
    status == "unlisted"
  end

  def draft?
    status == "draft"
  end

  def public?
    published? || unlisted?
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

  private

  def calculate_url_name
    if metadata["title"].present?
      metadata["title"].parameterize
    else
      File.basename(file_path, ".md")
    end
  end

  def ensure_url_name_in_metadata
    if metadata["url_name"].blank?
      metadata["url_name"] = calculate_url_name
    end
  end
end
