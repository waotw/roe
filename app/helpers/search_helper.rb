# frozen_string_literal: true

module SearchHelper
  # The four content directories. Anything else in a scope token is a post type.
  SEARCH_SOURCES = %w[posts pages documentation products].freeze

  # Scope hash for the header search on the current page (or nil = site-wide).
  #
  # Precedence:
  #   1. a page's `search_scope` frontmatter (author-declared, wins)
  #   2. auto-scope to the type of content being viewed — a documentation
  #      article, a product, or a post (scoped to the post's own post_type so
  #      "more like this" is one click)
  #   3. otherwise nil — a plain page is a container, so it stays site-wide
  #      unless the author sets `search_scope`.
  def site_search_scope
    # Duck-typed, not `@page`/`@post` truthiness — CollectionsController reuses
    # @page as the pagination number (an Integer), so guard the method calls.
    if @page.respond_to?(:metadata) && (raw = @page.metadata["search_scope"]).present?
      return parse_search_scope(raw)
    end

    # Collection archive page (/collections/...) — scope to its own filters.
    if @source.present?
      return collection_scope(@source, @post_type, @tags)
    end

    return { sources: [ "documentation" ] } if @doc
    return { sources: [ "products" ] } if @product
    if @post.respond_to?(:post_type)
      post_type = @post.post_type.to_s.strip
      return post_type.empty? ? { sources: [ "posts" ] } : { postTypes: [ post_type ] }
    end

    nil
  end

  # Build a scope hash from a collection's filter primitives. `source` may be
  # nested ("documentation/guides") — the base directory is the source.
  def collection_scope(source, post_type, tags)
    base = source.to_s.split("/").first
    scope = {}
    scope[:sources] = [ base ] if SEARCH_SOURCES.include?(base)
    scope[:postTypes] = [ post_type.to_s ] if post_type.present?
    scope[:tagsInclude] = Array(tags).map(&:to_s) if tags.respond_to?(:any?) && tags.any?
    scope.presence
  end

  # Parse a `search_scope` frontmatter string into a scope hash. Tokens split
  # on spaces / commas / slashes; a token naming a content directory is a
  # source, anything else is a post type (e.g. "podcast", "audio").
  def parse_search_scope(raw)
    tokens = raw.to_s.split(%r{[\s,/]+}).map(&:strip).reject(&:empty?)
    return nil if tokens.empty?

    sources = tokens & SEARCH_SOURCES
    post_types = tokens - SEARCH_SOURCES

    scope = {}
    scope[:sources] = sources if sources.any?
    scope[:postTypes] = post_types if post_types.any?
    scope.presence
  end
end
