# Named feeds, read from site/system/features/feeds.yml. The file's presence is
# what enables the feature (like the other features/*.yml). Each entry is a
# collection query (source/post_type/tags/category/order/limit) plus feed
# metadata (title/description) and an audience:
#
#   articles:
#     title: "Articles"
#     source: posts
#     post_type: article
#     order: date
#     limit: 20
#     audience: free      # free (default) | paid
#
# free  → public feed at /feed/<name>.xml (+ .atom), paid content excluded.
# paid  → token-gated (like the private podcast feed), includes everything.
#
# An absent file means no feeds — never an error.
class FeedConfig
  # Names that collide with the built-in /feed.* routes or read oddly as a
  # slug. A feed may not use one.
  RESERVED_NAMES = %w[feed xml atom rss].freeze

  FILE = SiteConfig::FEATURES_PATH.join("feeds.yml")

  # The feature is on when the file exists (matches SiteConfig.feature_enabled?).
  def self.enabled?
    File.exist?(FILE)
  end

  def self.all_feeds
    config = SiteConfig.current("features/feeds")&.config
    config.is_a?(Hash) ? config : {}
  end

  def self.feed_names
    all_feeds.keys.reject { |name| reserved?(name) }
  end

  def self.get(name)
    return nil if name.blank? || reserved?(name)
    all_feeds[name.to_s]
  end

  def self.exists?(name)
    get(name).present?
  end

  def self.paid?(name)
    get(name).to_h["audience"].to_s.strip.downcase == "paid"
  end

  def self.reserved?(name)
    RESERVED_NAMES.include?(name.to_s.strip.downcase)
  end

  def self.reload!
    SiteConfig.reload!("features/feeds")
  end
end
