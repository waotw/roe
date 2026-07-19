# frozen_string_literal: true

# Single source of truth for the ```card builder — the modal the editor pops up
# so authors can discover and fill card options per type. Cards are one ```card
# fence with a `type:` line; the renderer dispatches on it (see
# HasMarkdownExtensions#render_card). Each field maps 1:1 to a key the matching
# render_<type> method reads.
#
# Product is intentionally absent — it's a separate @placeholder markdown
# template, not a ```card type.
#
# Field shape mirrors CollectionBuilderSchema: key, type (:text / :textarea /
# :select / :boolean), label, hint, and (for :select) options. Booleans are
# tri-state (unset / true / false) so "use the engine default" stays distinct
# from an explicit false. Only fields the author sets get written.
module CardBuilderSchema
  # Ordered for the type selector at the top of the modal.
  TYPES = [
    { value: "pullquote",    label: "Pull quote" },
    { value: "post-link",    label: "Post link" },
    { value: "aside",        label: "Aside" },
    { value: "product-link", label: "Product link" }
  ].freeze

  FIELDS_BY_TYPE = {
    "pullquote" => [
      { key: "text", type: :textarea, label: "Quote",
        hint: "The quote itself. Markdown is allowed." },
      { key: "position", type: :select, label: "Position",
        options: %w[left center right],
        hint: "Defaults to center if blank" },
      { key: "attribution", type: :text, label: "Attribution",
        hint: "Who said it, e.g., “Shakespeare”." }
    ],

    "aside" => [
      { key: "text", type: :textarea, label: "Text",
        hint: "Body text. Leave blank for an image-only aside." },
      { key: "image", type: :text, label: "Image",
        hint: "Image URL/path to show in the aside." },
      { key: "link", type: :text, label: "Link",
        hint: "URL the aside links to. Leave blank and no link will be added." },
      { key: "link_text", type: :text, label: "Link text",
        hint: "Custom label for the link. Defaults to →." }
    ],

    "post-link" => [
      { key: "post", type: :post_search, label: "Post",
        hint: "Search for a post, page, product, or doc to link. Its title, excerpt, image, etc. are pulled in automatically." },
      { key: "style", type: :select, label: "Style",
        options: %w[small medium large],
        hint: "Card layout. Defaults to small." },
      { key: "title", type: :text, label: "Title",
        hint: "Override the title pulled from the linked item." },
      { key: "subtitle", type: :text, label: "Subtitle",
        hint: "Override the subtitle." },
      { key: "show_subtitle", type: :boolean, label: "Show subtitle",
        hint: "Show the subtitle. Defaults on for medium/large, off for small." },
      { key: "excerpt", type: :textarea, label: "Excerpt",
        hint: "Override the excerpt pulled from the linked item." },
      { key: "show_excerpt", type: :boolean, label: "Show excerpt",
        hint: "Show the excerpt on small/medium cards too — large always shows it." },
      { key: "url", type: :text, label: "URL",
        hint: "Override the link target (defaults to the linked item's URL)." },
      { key: "link_text", type: :text, label: "Link text",
        hint: "Label for the read-more link. Defaults to “Read full story →”." },
      { key: "author", type: :text, label: "Author",
        hint: "Override the author (posts only)." },
      { key: "date", type: :text, label: "Date",
        hint: "Override the date (posts only)." },
      { key: "image", type: :text, label: "Image",
        hint: "Override the featured image. Use “none” to suppress it." }
    ],

    # Product-link renders as a live post-link card pointed at a product, so
    # its fields mirror post-link's (minus author/date, which products lack).
    "product-link" => [
      { key: "product", type: :product_search, label: "Product",
        hint: "Search for a product to link. Its title, price, image, and description are pulled in automatically." },
      { key: "style", type: :select, label: "Style",
        options: %w[small medium large],
        hint: "Card layout. Defaults to small." },
      { key: "title", type: :text, label: "Title",
        hint: "Override the title pulled from the product." },
      { key: "description", type: :textarea, label: "Description",
        hint: "Override the description pulled from the product." },
      { key: "show_description", type: :boolean, label: "Show description",
        hint: "Show the product's description on the card. On by default." },
      { key: "url", type: :text, label: "URL",
        hint: "Override the link target (defaults to the product's page)." },
      { key: "link_text", type: :text, label: "Link text",
        hint: "Label for the link. Defaults to “View product →”." },
      { key: "image", type: :text, label: "Image",
        hint: "Override the product image. Use “none” to suppress it." }
    ]
  }.freeze

  # "Core" fields identify the card and can't be derived from anything else.
  # For post-link, everything after these is an override of a value that's
  # otherwise pulled live from the linked post — so the builder shows a divider
  # and note between them. Empty for types with no referenced source.
  CORE = {
    "post-link"    => %w[post style],
    "product-link" => %w[product style]
  }.freeze

  # What each type needs to render something meaningful. `all` keys must all be
  # present; `any` means at least one of them must be. Drives the required
  # markers in the form and the insert-time validation.
  REQUIRED = {
    "pullquote"    => { all: %w[text] },
    "aside"        => { any: %w[text image] },
    "post-link"    => { all: %w[post] },
    "product-link" => { all: %w[product] }
  }.freeze

  # cards.yml key holding each type's button_template (the author-editable
  # defaults). post-link's key uses an underscore.
  TEMPLATE_KEYS = {
    "pullquote"    => "pullquote_button_template",
    "aside"        => "aside_button_template",
    "post-link"    => "post_link_button_template",
    "product-link" => "product_link_button_template"
  }.freeze

  def self.types
    TYPES
  end

  def self.fields_for(type)
    FIELDS_BY_TYPE[type] || []
  end

  def self.required_for(type)
    REQUIRED[type] || {}
  end

  def self.core_for(type)
    CORE[type] || []
  end

  # A type's button_template (raw YAML-ish text from cards.yml) parsed into a
  # { key => value } hash the builder uses to pre-fill fields. `type:` itself
  # and the placeholder token are dropped, as are unknown keys. Returns {}.
  def self.default_values(type, template_text = nil)
    template_text ||= SiteConfig.default("cards", TEMPLATE_KEYS[type])
    return {} if template_text.blank?

    keys = fields_for(type).map { |f| f[:key] }
    template_text.to_s.each_line.each_with_object({}) do |line, acc|
      next if line.strip.empty?

      key, value = line.split(":", 2).map { |s| s.to_s.strip }
      next if key.blank? || value.blank?

      value = "" if value == "__PLACEHOLDER__"
      acc[key] = value if keys.include?(key) && value.present?
    end
  end
end
