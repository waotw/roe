# frozen_string_literal: true

# Serves the public search index consumed by the client-side site search.
# The static build writes the same JSON to search-index.json so search works
# with no backend; this endpoint covers dynamic (Rails-served) sites.
class SearchController < ApplicationController
  skip_before_action :require_authentication

  def index
    # Self-invalidating cache: the key changes whenever any content is
    # updated or the paid-teaser setting flips, so we never serve stale
    # results but still avoid rebuilding on every request.
    json = Rails.cache.fetch(cache_key) { SearchIndexGenerator.build.to_json }
    render json: json
  end

  private

  def cache_key
    stamp = [ Post, Page, Documentation, Product ].filter_map { |m| m.maximum(:updated_at) }.max
    paid = SiteConfig.feature("members", "everyone.show_paid_content")
    # Bump the version whenever the index's shape/contents logic changes
    # (content timestamps alone won't invalidate a code-only change).
    [ "search_index", "v2", stamp, paid ]
  end
end
