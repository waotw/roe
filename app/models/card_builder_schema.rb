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
    { value: "product-link", label: "Product link" },
    { value: "player",       label: "Player" }
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
      { key: "link_url", type: :text, label: "Link URL",
        hint: "Makes the whole aside a link — image and all. Put links inside the text instead if you only want part of it to be clickable." }
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
    ],

    "player" => [
      { key: "audio", type: :text, label: "Audio",
        hint: "Audio file to play. Defaults to the post's own audio." },
      { key: "title", type: :text, label: "Title",
        hint: "Defaults to the post's title." },
      { key: "image", type: :text, label: "Artwork",
        hint: "Defaults to the post's image, then the release/podcast cover." },
      { key: "show_artwork", type: :boolean, label: "Show artwork",
        hint: "Show the artwork. On by default." }
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

  # Booleans whose default depends on the card's style — off for small, on for
  # medium and large (show_excerpt: large only). A site that wants one of them
  # on everywhere can say so in cards.yml; absent, the style rule stands, which
  # is what every install already has.
  STYLE_DEFAULT_SETTINGS = {
    "show_subtitle" => "default_show_subtitle",
    "show_excerpt"  => "default_show_excerpt"
  }.freeze

  # true/false when a site setting has fixed this default for every style, nil
  # when the style rule still decides. A blank setting counts as unset — the
  # config editor writes an empty string for a field nobody filled in.
  def self.setting_default(type, key)
    setting_key = STYLE_DEFAULT_SETTINGS[key.to_s] or return nil

    value = SiteConfig.default("cards", type.to_s)&.[](setting_key)
    return nil if value.nil? || value.to_s.strip.empty?

    value.to_s.strip.casecmp("true").zero?
  end

  # What the builder's "—" option will actually do, so the menu says it rather
  # than leaving the author to guess. Leaving it unset keeps the key out of the
  # card, which is what lets the card follow the setting later.
  def self.default_label(type, key)
    fixed = setting_default(type, key)
    return "default: #{fixed ? 'on' : 'off'}" unless fixed.nil?
    return "default: by style" if STYLE_DEFAULT_SETTINGS.key?(key.to_s)

    "default"
  end

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

  # What the builder shows for each field before the author touches it, read
  # from the site's card defaults: field `style` takes its value from
  # `default_style` under that card type in cards.yml.
  #
  # This used to be parsed out of a per-type `button_template` — a block of
  # YAML-ish text that the editor once pasted straight into the document. The
  # builders replaced that insert path, leaving the templates as a second,
  # invisible copy of settings the config already had. cards.yml carried both
  # `default_style: small` and a template saying `style: small`, and only one
  # of them was on the settings form.
  #
  # A value equal to the default is left out of the card on insert (see the
  # builder's insert()), so the card keeps following the setting if it changes.
  def self.default_values(type)
    settings = SiteConfig.default("cards", type.to_s)
    return {} unless settings.is_a?(Hash)

    fields_for(type).each_with_object({}) do |field, acc|
      value = settings["default_#{field[:key]}"].to_s.strip
      acc[field[:key]] = value if value.present?
    end
  end
end
