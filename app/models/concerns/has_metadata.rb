module HasMetadata
  extend ActiveSupport::Concern

  included do
    before_save :ensure_url_name_in_metadata
  end

  # Shared accessors
  def url_name
    metadata["url_name"] || calculate_url_name
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

  # Status methods (shared by both)
  def status
    metadata["status"] || "draft"
  end

  def published?
    status == "published"
  end

  def draft?
    status == "draft"
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
      File.basename(file_path, '.md')
    end
  end

  def ensure_url_name_in_metadata
    if metadata["url_name"].blank?
      metadata["url_name"] = calculate_url_name
    end
  end

  # Class methods
  class_methods do
    def published
      where("json_extract(metadata, '$.status') = ?", "published")
    end

    def drafts
      where("json_extract(metadata, '$.status') = ?", "draft")
    end
  end
end
