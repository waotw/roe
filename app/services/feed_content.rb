# Resolves a named feed's config (a feeds.yml entry) to its ordered, limited
# posts. Shared by FeedsController (live requests) and StaticGenerator (build),
# so the two never disagree about a feed's contents. Selection and ordering come
# from CollectionQuery — the same path collections use.
#
# include_paid: false (the default, and the only mode a public/static feed ever
# uses) hard-excludes paid content so it can't leak. A paid feed passes true
# once the caller has authenticated the request.
class FeedContent
  # show_paid_teasers: keep paid posts in a public feed so they can be shown as
  # previews. Off (the default) they're dropped entirely, which is what a site
  # that would rather not advertise to non-members wants.
  def self.for(feed_config, include_paid: false, show_paid_teasers: false)
    new(feed_config, include_paid: include_paid, show_paid_teasers: show_paid_teasers).posts
  end

  def initialize(feed_config, include_paid: false, show_paid_teasers: false)
    @config = (feed_config || {}).symbolize_keys
    @include_paid = include_paid
    @show_paid_teasers = show_paid_teasers
  end

  def posts
    records = CollectionQuery.new(@config).records || []
    records = exclude_paid(records) unless @include_paid || @show_paid_teasers
    ordered = CollectionQuery.order_items(records, @config[:order].presence || "date")
    limit.positive? ? ordered.first(limit) : ordered
  end

  private

  # Only meaningful when members is on; works for a relation or the Array a
  # `collection:` membership filter returns.
  def exclude_paid(records)
    return records unless SiteConfig.feature_enabled?("members")
    records.to_a.reject { |p| p.respond_to?(:audience) && p.audience == "paid" }
  end

  def limit
    @limit ||= (@config[:limit].presence || 20).to_i
  end
end
