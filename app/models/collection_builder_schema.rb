# frozen_string_literal: true

# Single source of truth for the ```collection builder — the form the editor
# pops up so authors can discover and fill collection options without
# memorising the YAML-ish syntax. Each field maps 1:1 to a key read by
# HasMarkdownExtensions#parse_collection_config / #render_collection.
#
# The same schema is meant to (eventually) generate the options table in the
# collections documentation, so keep labels/hints authored for humans.
#
# Field shape:
#   key         — the YAML key emitted into the block (String)
#   type        — :text, :select, or :boolean (tri-state: unset / true / false)
#   label       — form label
#   hint        — tooltip / helper text
#   options     — for :select, the allowed values
#   depends_on  — { field:, value: } — only show when another field equals value
#
# Booleans are tri-state on purpose: "unset" (blank) omits the key so the
# engine's own default applies, while true/false force the value. This matches
# the builder's rule — only fields the author actually sets get written.
module CollectionBuilderSchema
  FIELDS = [
    { key: "source", type: :select, label: "Source",
      options: %w[posts pages documentation products],
      hint: "Which content to pull from. Defaults to posts." },

    { key: "heading", type: :text, label: "Heading",
      hint: "Optional section heading shown above the collection." },

    { key: "template", type: :select, label: "Template",
      options: %w[list grid compact links full glossary],
      hint: "How each item is displayed. Products default to grid; everything else to list." },

    { key: "limit", type: :text, label: "Limit",
      hint: "Max items to show — a number, or \"all\". Defaults to the site setting (10)." },

    { key: "order", type: :select, label: "Order",
      options: %w[date date-asc title filename],
      hint: "Sort order. date is newest-first (default); date-asc is oldest-first." },

    { key: "offset", type: :text, label: "Offset",
      hint: "Skip the first N items (e.g. to show a second page)." },

    { key: "post_type", type: :select, label: "Post type",
      options: %w[all article audio video podcast],
      hint: "Filter posts by type. Only applies when the source is posts.",
      depends_on: { field: "source", value: "posts" } },

    { key: "podcast", type: :text, label: "Podcast",
      hint: "Show only episodes for this podcast key. Posts only.",
      depends_on: { field: "source", value: "posts" } },

    { key: "tags", type: :text, label: "Tags",
      hint: "Comma-separated tags to include. Prefix a tag with - to exclude it." },

    { key: "related", type: :boolean, label: "Related only",
      hint: "Show only items linked from this page's frontmatter `related:` list." },

    { key: "show_author", type: :boolean, label: "Show author",
      hint: "Show each item's author." },

    { key: "show_excerpt", type: :boolean, label: "Show excerpt",
      hint: "Show each item's excerpt. On by default for the full template." },

    { key: "show_date", type: :boolean, label: "Show date",
      hint: "Show each item's date. On by default for the compact template." },

    { key: "show_subtitle", type: :boolean, label: "Show subtitle",
      hint: "Show each item's subtitle." },

    { key: "show_more", type: :boolean, label: "\"View all\" link",
      hint: "Add a link to the full listing below the collection. Posts only." },

    { key: "show_more_text", type: :text, label: "\"View all\" text",
      hint: "Custom label for the View all link.",
      depends_on: { field: "show_more", value: "true" } },

    # --- Products only -------------------------------------------------------
    { key: "category", type: :text, label: "Category",
      hint: "Filter products by category.",
      depends_on: { field: "source", value: "products" } },

    { key: "groups", type: :boolean, label: "Group variants",
      hint: "Collapse product variants into one entry per group.",
      depends_on: { field: "source", value: "products" } },

    { key: "aspect_ratio", type: :select, label: "Image ratio",
      options: %w[auto portrait square landscape],
      hint: "Product image aspect ratio.",
      depends_on: { field: "source", value: "products" } },

    { key: "show_description", type: :boolean, label: "Show description",
      hint: "Show each product's description.",
      depends_on: { field: "source", value: "products" } }
  ].freeze

  def self.fields
    FIELDS
  end

  # The install's button_template (raw YAML-ish text from collections.yml),
  # parsed into a { key => value } hash the builder uses to pre-fill fields —
  # so a site's commonly-used options become the builder's defaults. Anything
  # that isn't a known field is ignored. Returns {} when unset/blank.
  def self.default_values(template_text = nil)
    template_text ||= SiteConfig.default("collections", "button_template")
    return {} if template_text.blank?

    keys = FIELDS.map { |f| f[:key] }
    template_text.to_s.each_line.each_with_object({}) do |line, acc|
      next if line.strip.empty?

      key, value = line.split(":", 2).map { |s| s.to_s.strip }
      next if key.blank? || value.blank?
      # Ignore the placeholder token the raw insert used for cursor-parking.
      value = "" if value == "__PLACEHOLDER__"
      acc[key] = value if keys.include?(key) && value.present?
    end
  end
end
