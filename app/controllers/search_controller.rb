# frozen_string_literal: true

# Serves the search index consumed by the client-side site search.
#
# /search-index.json is public and identical to what the static build
# writes. /members/search-index.json is the same shape with paid posts'
# full text, served only to a signed-in paid member — the public file
# can never carry paid bodies because it's one file for everyone (and a
# plain static asset on a static site). See SearchIndexGenerator.
class SearchController < ApplicationController
  skip_before_action :require_authentication

  def index
    render json: cached_index(:public)
  end

  def members
    unless can_access_premium?
      head :forbidden
      return
    end
    render json: cached_index(:paid)
  end

  private

  # Self-invalidating cache: the key changes whenever any content is
  # updated or the paid-teaser setting flips, so we never serve stale
  # results but still avoid rebuilding on every request.
  def cached_index(audience)
    Rails.cache.fetch(cache_key(audience)) { SearchIndexGenerator.build(audience: audience).to_json }
  end

  def cache_key(audience)
    stamp = [ Post, Page, Documentation, Product ].filter_map { |m| m.maximum(:updated_at) }.max
    paid = SiteConfig.feature("members", "everyone.show_paid_content")
    # Bump the version whenever the index's shape/contents logic changes
    # (content timestamps alone won't invalidate a code-only change).
    [ "search_index", "v3", audience, stamp, paid ]
  end
end
