# frozen_string_literal: true

# Single source of truth for the ```gallery block — the GALLERY dropdown in the
# editor and the directive checking in HasMarkdownExtensions both read from
# here, so the menu can't offer something the renderer ignores, and the checker
# can't flag something the docs teach.
#
# A gallery body is images (`![alt](src)`) plus a few `key: value` directive
# lines. parse_gallery whitelists those keys so stray "Word: text" lines stay
# content rather than turning into config — which also means a mistyped
# directive isn't ignored so much as silently swallowed.
module GalleryBuilderSchema
  DIRECTIVES = %w[slideshow caption aspect_ratio].freeze

  # Names that mean a directive but aren't one.
  #
  # `carousel` is what Roe calls this everywhere except the markdown: the
  # builder's checkbox says "Display as carousel?", the docs heading says
  # "Carousel (slideshow)", the rendered class is `gallery-carousel`. Only the
  # directive is `slideshow`, so `carousel: true` gets typed and does nothing.
  # Kept as a rejected alias rather than accepted as a synonym — one name for
  # one thing, and the writer is told which name.
  ALIASES = { "carousel" => "slideshow" }.freeze

  # Every shape a gallery can give its images, as the `gallery-ratio-<value>`
  # classes the themes define. Several are synonyms — `tv` and `landscape` are
  # both 4:3, `cinema` and `film` both 21:9, `auto` and `original` both natural
  # size — so the menu below offers one name per shape while all of these stay
  # valid to type. The docs use `film`.
  #
  # Open by design: a theme can define a ratio class of its own. So this is a
  # spell-checking dictionary, never an allowlist — an unknown value that isn't
  # close to one of these is left alone.
  RATIOS = %w[square portrait tv landscape wide cinema film original auto].freeze

  # One entry per distinct shape, for the builder's dropdown. The ratio is in
  # the label because "TV" and "Cinema" don't say much on their own.
  MENU_RATIOS = [
    { value: "square",   label: "Square (1:1)" },
    { value: "portrait", label: "Portrait (3:4)" },
    { value: "tv",       label: "TV (4:3)" },
    { value: "wide",     label: "Wide (16:9)" },
    { value: "cinema",   label: "Cinema (21:9)" },
    { value: "original", label: "Original (unchanged)" }
  ].freeze
end
