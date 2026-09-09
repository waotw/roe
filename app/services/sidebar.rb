# frozen_string_literal: true

# What the sidebar covers, asked from outside a view.
#
# This lived in LayoutHelper, which meant only the layout could ask. The
# metadata editor needs the same answers — whether to offer a `show_sidebar`
# field at all, and what it should default to — and a helper reachable only
# from a rendering view can't supply them.
#
# The rules, in order:
#
#   No sidebar file       → no sidebar anywhere. The field is pointless, so
#                           the editor doesn't offer it.
#   No scope (or "all")   → the sidebar is on for the whole site.
#   A scope               → on only for the content types it names.
#
# A file's own `show_sidebar` overrides whatever this says. That's
# LayoutHelper's job; this only answers what happens without one.
class Sidebar
  FILE = -> { File.join(RoeSitePaths::SITE_PATH, "layout", "sidebar.md") }

  # The content types a scope can name, matching what LayoutHelper works out
  # from the current request.
  TYPES = %w[posts pages documentation products].freeze

  # Editor resource types are singular; scopes are plural.
  RESOURCE_TYPES = { "post" => "posts", "page" => "pages", "product" => "products",
                     "documentation" => "documentation" }.freeze

  class << self
    def path = FILE.call

    def exists? = File.exist?(path)

    # The scope as a list. "all" means every type.
    def scope
      return [ "all" ] unless exists?

      value = frontmatter["scope"] || "all"
      case value
      when String then value.split(",").map(&:strip).reject(&:blank?).presence || [ "all" ]
      when Array  then value.map(&:to_s)
      else             [ "all" ]
      end
    end

    # Whether the sidebar shows for this content type when the file says
    # nothing. `type` may be singular (the editor's resource type) or plural.
    def covers?(type)
      return false unless exists?

      plural = RESOURCE_TYPES.fetch(type.to_s, type.to_s)
      s = scope
      s.include?("all") || s.include?(plural)
    end

    def frontmatter
      return {} unless exists?

      parsed = FrontMatterParser::Parser.parse_file(path)
      parsed.front_matter || {}
    rescue StandardError => e
      Rails.logger.error "[Sidebar] Couldn't parse #{path}: #{e.message}"
      {}
    end
  end
end
