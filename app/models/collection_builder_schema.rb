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
#   depends_on  — visibility condition(s): one { field:, value: } (equals) or
#                 { field:, in: [...] } (one of), or an array of those (all must
#                 hold). A hidden field's value is never written to the block.
#   docs        — optional path/URL to fuller docs; rendered as a "Learn more"
#                 link after the hint (opens in a new tab). For options the hint
#                 can't fully explain on its own.
#
# Booleans are tri-state on purpose: "unset" (blank) omits the key so the
# engine's own default applies, while true/false force the value. This matches
# the builder's rule — only fields the author actually sets get written.
module CollectionBuilderSchema
  FIELDS = [
    { key: "heading", type: :text, label: "Heading",
      hint: "Optional section heading shown above the collection." },

    { key: "source", type: :select, label: "Source",
      options: %w[posts pages documentation products],
      hint: "Which content to pull from. Defaults to posts." },

    { key: "post_type", type: :select, label: "Post type",
      options: %w[all article audio video podcast music],
      hint: "Filter posts by type. Only applies when the source is posts.",
      depends_on: { field: "source", value: "posts" } },

    { key: "podcast", type: :text, label: "Podcast",
      hint: "Show only episodes for this podcast key.",
      depends_on: [
        { field: "source", value: "posts" },
        { field: "post_type", value: "podcast" }
      ] },

    # Release is to music what podcast is to episodes — a separate axis, so a
    # track can belong to a release, a podcast, or both.
    { key: "release", type: :text, label: "Release",
      hint: "Show only tracks from this release key (its key in music.yml).",
      depends_on: [
        { field: "source", value: "posts" },
        { field: "post_type", value: "music" }
      ] },

    # Collections show published items only unless this is on. Mainly for
    # playlists that gather tracks not listed on their own.
    { key: "show_unlisted", type: :boolean, label: "Include unlisted",
      hint: "Also include unlisted posts. Off by default.",
      depends_on: { field: "source", value: "posts" } },

    { key: "tags", type: :text, label: "Tags",
      hint: "Comma-separated tags to include. Prefix a tag with - to exclude it." },

    # `grid` is intentionally not in this base list — it only makes sense for
    # products, so the controller adds it as an option (and pre-selects it)
    # when the source is products, and removes it otherwise.
    { key: "template", type: :select, label: "Template",
      options: %w[list compact links menu full glossary playlist],
      hint: "How each item is displayed. Products default to grid; everything else to list. menu is a bare link list you can hand-order and send content to. playlist is a track/episode list a player card can drive." },

    # --- Menu group: shown only when the template is `menu` ------------------
    { key: "style", type: :select, label: "Menu style",
      options: %w[vertical horizontal],
      hint: "Layout for the menu template's link list. Defaults to vertical.",
      depends_on: { field: "template", value: "menu" } },

    { key: "collection", type: :text, label: "Collection name",
      hint: "Name this menu so you can send content here. Add the same `collection: <name>` to any page, post, or product and it will be in this collection — sent content is combined with the order list below.",
      docs: "/documentation/roe/collections_templates#why-give-the-collection-a-name",
      depends_on: { field: "template", value: "menu" } },

    # For a menu, `order:` is a hand-picked url_name list (membership + order),
    # so it's free text. Shares the `order` key with the sort select below;
    # they're mutually exclusive, so only one is ever visible or written.
    { key: "order", type: :text, label: "Order",
      hint: "Comma-separated url_names, in the order you want them (e.g. home, blog, about). Listed items come first; anything tagged with this menu's collection name follows.",
      depends_on: { field: "template", value: "menu" } },

    # --- Feed group: every non-menu template. "Not menu" is spelled out as the
    # other templates plus blank (the default). --------------------------------
    # The ordered-media sorts (track_number / episode_number / chapter_number)
    # are offered only when their feature is on — for everyone else they're
    # noise. Callable so the gate is read per request, not frozen at boot.
    { key: "order", type: :select, label: "Order",
      options: -> { %w[date date-asc title filename] + CollectionQuery.enabled_numbered_sorts },
      hint: "Sort order. date is newest-first (default); date-asc is oldest-first. For a hand-picked order, type a comma-separated list of url_names into the block instead (e.g. order: blog, about, store).",
      depends_on: { field: "template", in: [ "", "list", "grid", "compact", "links", "full", "glossary", "playlist" ] } },

    { key: "limit", type: :text, label: "Limit",
      hint: "Max items to show — a number, or \"all\". Defaults to the site setting (10).",
      depends_on: { field: "template", in: [ "", "list", "grid", "compact", "links", "full", "glossary", "playlist" ] } },

    { key: "offset", type: :text, label: "Offset",
      hint: "Skip the first N items (e.g. to show a second page).",
      depends_on: { field: "template", in: [ "", "list", "grid", "compact", "links", "full", "glossary", "playlist" ] } },

    # Non-menu counterpart of the `collection` field above: for a feed it's a
    # membership filter (show only content tagged with this name). Menus put it
    # in their own group; every other template gets it here, above `related`.
    { key: "collection", type: :text, label: "Collection name",
      hint: "Show only content tagged with `collection: <name>` in its metadata. (For the menu template, this instead names the menu so you can send content to it.)",
      docs: "/documentation/roe/collections_templates#why-give-the-collection-a-name",
      depends_on: { field: "template", in: [ "", "list", "grid", "compact", "links", "full", "glossary", "playlist" ] } },

    { key: "related", type: :boolean, label: "Related",
      hint: "When set to \"true\", only items connected through metadata will be in results",
      docs: "/documentation/roe/collections#show-related-content",
      depends_on: { field: "template", in: [ "", "list", "grid", "compact", "links", "full", "glossary", "playlist" ] } },

    # --- Display toggles: each only appears for the templates it affects.
    # list/compact/full carry meta; excerpt is full-only. ---------------------
    { key: "show_subtitle", type: :boolean, label: "Show subtitle",
      hint: "Show each item's subtitle. On by default for list and full; off for compact.",
      depends_on: { field: "template", in: [ "", "list", "compact", "full" ] } },

    { key: "show_author", type: :boolean, label: "Show author",
      hint: "Show each item's author. Off by default.",
      depends_on: { field: "template", in: [ "", "list", "compact", "full" ] } },

    { key: "show_date", type: :boolean, label: "Show date",
      hint: "Show each item's date. On by default.",
      depends_on: { field: "template", in: [ "", "list", "compact", "full" ] } },

    { key: "show_excerpt", type: :boolean, label: "Show excerpt",
      hint: "Show each item's excerpt. On by default. Full template only.",
      depends_on: { field: "template", value: "full" } },

    { key: "show_more", type: :boolean, label: "\"View all\" link",
      hint: "Add a link to the full listing below the collection. Posts only.",
      depends_on: { field: "source", value: "posts" } },

    { key: "show_more_text", type: :text, label: "\"View all\" text",
      hint: "Custom label for the View all link.",
      depends_on: [
        { field: "source", value: "posts" },
        { field: "show_more", value: "true" }
      ] },

    # --- Products only -------------------------------------------------------
    { key: "category", type: :text, label: "Category",
      hint: "Filter products by category.",
      depends_on: { field: "source", value: "products" } },

    { key: "groups", type: :boolean, label: "Group variants",
      hint: "Collapse product variants into one entry per group.",
      depends_on: { field: "source", value: "products" } },

    { key: "aspect_ratio", type: :select, label: "Image ratio",
      # Offered set only; `auto`, `landscape`, and `film` are accepted aliases
      # that resolve to the same ratios in CSS (original/tv/cinema).
      options: %w[square portrait tv wide cinema original],
      hint: "Product image aspect ratio.",
      depends_on: { field: "source", value: "products" } },

    { key: "show_description", type: :boolean, label: "Show description",
      hint: "Show each product's description.",
      depends_on: { field: "source", value: "products" } }
  ].freeze

  def self.fields
    FIELDS
  end

  # A select's options, resolving a callable (a feature-gated list) to an Array.
  # Callers should use this rather than reading field[:options] directly.
  def self.options_for(field)
    opts = field[:options]
    opts.respond_to?(:call) ? Array(opts.call) : Array(opts)
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
