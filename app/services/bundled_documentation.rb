# frozen_string_literal: true

# The copy of Roe's own documentation that ships inside the app, used when the
# installed copy under /site isn't there.
#
# Roe installs its docs into site/documentation/roe/ so they travel with the
# site, are editable, and work offline. But they're the user's files: they can
# be deleted, renamed, or never installed. When that happens every admin link
# into them 404s — including the ones that appear precisely when something has
# gone wrong and you most need the page.
#
# The same files already exist at lib/site_templates/minimum/documentation/roe/,
# because that's what the installer copies from. So this is a fallback, not a
# second copy to keep in step: one source, read from a different place when the
# installed one is missing.
#
# The installed copy always wins. Someone who edits their docs should see their
# edits, and someone who deletes a page should still be able to follow a link
# to it rather than hitting a dead end.
class BundledDocumentation
  ROOT = Rails.root.join("lib", "site_templates", "minimum", "documentation")

  class << self
    # An unsaved Documentation for `url_name` inside `scope` ("roe"), or nil.
    # Unsaved on purpose — it isn't the user's content and mustn't appear in
    # their documentation lists, search, or exports.
    def find(scope, url_name)
      path = index(scope)[url_name.to_s]
      return nil unless path

      parsed = FrontMatterParser::Parser.parse_file(path)
      Documentation.new(file_path: path.to_s, content: parsed.content,
                        metadata: parsed.front_matter)
    rescue StandardError => e
      Rails.logger.warn "[BundledDocumentation] couldn't read #{path}: #{e.message}"
      nil
    end

    def available?(scope) = index(scope).any?

    private

    # url_name → path, built once. url_name comes from the front matter, so
    # the file has to be read to know it — doing that per request would parse
    # every bundled doc on every miss.
    #
    # Cached rather than memoized in a constant so a dev editing the bundled
    # copy doesn't have to restart, and so the cache clears with everything
    # else on deploy.
    def index(scope)
      dir = safe_scope_dir(scope)
      return {} unless dir

      Rails.cache.fetch("bundled_docs_index/#{scope}", expires_in: 1.hour) do
        Dir.glob(dir.join("*.md")).each_with_object({}) do |path, map|
          front = FrontMatterParser::Parser.parse_file(path).front_matter
          name = front["url_name"].presence || File.basename(path, ".md").parameterize
          map[name] = path
        rescue StandardError
          next # one unreadable file shouldn't cost the whole index
        end
      end
    end

    # The scope comes off the URL, so it can't be joined onto a path unchecked.
    def safe_scope_dir(scope)
      name = scope.to_s
      return nil unless name.match?(/\A[a-z0-9_-]+\z/i)

      dir = ROOT.join(name)
      dir.directory? ? dir : nil
    end
  end
end
