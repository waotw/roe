module HasMetadata
  extend ActiveSupport::Concern

  # At module level, not inside `included do` — that block runs once per
  # including class, so defining the constant there redefined it for every
  # model and warned "already initialized constant" on boot.
  #
  # A missing status counts as a draft, matching #status below. The reader has
  # always defaulted to "draft" while the scopes matched the raw JSON, so an
  # item with no status belonged to no scope at all: missing from every total,
  # and called a draft by one half of the code and nothing by the other.
  #
  # Draft is the safe direction — an item nobody gave a status to shouldn't be
  # public, which is already how it behaves when served
  # (SiteController#check_draft_access! refuses anything not published or
  # unlisted).
  DRAFT_SQL = "COALESCE(NULLIF(json_extract(metadata, '$.status'), ''), 'draft')".freeze

  # True when an item has the tag (two binds, both the tag): whole tag, case
  # ignored, from a JSON array or a comma-separated string. lower() folds
  # ASCII letters only, so É and é stay different.
  def self.tag_match_sql(table)
    tags = "json_extract(#{table}.metadata, '$.tags')"
    type = "COALESCE(json_type(#{table}.metadata, '$.tags'), '')"
    "EXISTS (SELECT 1 FROM json_each(CASE #{type} WHEN 'array' THEN #{tags} ELSE '[]' END) AS t " \
      "WHERE lower(trim(t.value)) = lower(?)) " \
      "OR (#{type} = 'text' AND instr(',' || lower(replace(replace(#{tags}, ', ', ','), ' ,', ',')) || ',', " \
      "',' || lower(?) || ',') > 0)"
  end

  included do
    before_save :ensure_url_name_in_metadata

    # Status scopes — see DRAFT_SQL above for why a missing status is a draft.
    scope :published, -> {
      where("json_extract(metadata, '$.status') = ?", "published")
    }

    scope :unlisted, -> {
      where("json_extract(metadata, '$.status') = ?", "unlisted")
    }

    scope :drafts, -> {
      where("#{HasMetadata::DRAFT_SQL} = ?", "draft")
    }

    scope :not_draft, -> {
      where("#{HasMetadata::DRAFT_SQL} != ?", "draft")
    }

    scope :public_items, -> {
      where("json_extract(metadata, '$.status') IN (?, ?)", "published", "unlisted")
    }

    # Tag scopes. A tag matches whole and ignoring case: `lab` finds `lab`,
    # `Lab` and `LAB`, never `labs` or `lab-image`. Tags are a JSON array, or
    # a comma-separated string when written that way in the file.
    scope :tagged_with, ->(tags) {
      tag_array = Array(tags).map { |t| t.to_s.strip }.reject(&:empty?)
      return none if tag_array.empty?

      conditions = tag_array.map { "(#{HasMetadata.tag_match_sql(table_name)})" }
      where(conditions.join(" OR "), *tag_array.flat_map { |tag| [ tag, tag ] })
    }

    # The opposite of tagged_with for one tag; untagged items are kept.
    scope :not_tagged_with, ->(tag) {
      tag = tag.to_s.strip
      return all if tag.empty?

      where("NOT (#{HasMetadata.tag_match_sql(table_name)})", tag, tag)
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
        "[#{value.map { |item| item.is_a?(String) ? yaml_quoted(item) : format_yaml_scalar(item) }.join(', ')}]"
      when String
        if value.empty?
          '""'
        elsif value.match?(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/)
          "\"#{value}\""
        elsif value.include?("\n")
          yaml_block(value)
        else
          yaml_quoted(value)
        end
      else
        "\"#{value}\""
      end
    end

    # A value with lines, as a `|-` block. In double quotes YAML folds each
    # line break into a space, so a subtitle written on two lines came back
    # as one. `|2-` when the first line starts with a space, which YAML would
    # otherwise take for the block's indentation.
    def yaml_block(value)
      lines = value.gsub(/\r\n?/, "\n").sub(/\n+\z/, "").split("\n", -1)
      indicator = lines.first.to_s.match?(/\A\s/) ? "|2-" : "|-"
      ([ indicator ] + lines.map { |line| line.empty? ? "" : "  #{line}" }).join("\n")
    end

    # Double-quoted, with the backslash escaped as well as the quote: `C:\new`
    # written as-is reads back with a line break in it, or doesn't read.
    def yaml_quoted(value)
      escaped = value.gsub("\\") { "\\\\" }.gsub('"') { '\\"' }.gsub(/\r?\n/) { "\\n" }
      "\"#{escaped}\""
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

  # Collections this content opts into by name (e.g. `collection: nav`, or
  # `collection: footer, resources` for several). `collection:` is to placement
  # what `tags` is to topics: content declares which collections it belongs to,
  # and a `menu` collection gathers it by that name. Accepts a comma string or
  # an array; returns downcased names. Inert on its own — nothing happens until
  # a collection gathers the name, so it never renders as visible content on the
  # item itself.
  def collection_names
    raw = metadata["collection"]
    list = case raw
    when Array then raw
    when String then raw.split(",")
    else []
    end

    list.map { |c| c.to_s.strip.downcase }
        .reject(&:empty?)
        .uniq
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
