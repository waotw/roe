# frozen_string_literal: true

# The private feed URLs a member can subscribe to — one per podcast or music
# release that has paid content in it.
#
# A member could only reach these by finding an episode page first, which is a
# poor place to look when you've dropped the feed from your podcast app and
# want to re-add it. The account page is where people expect their own things
# to be.
#
# Returns URLs, never the bare token. The token has no meaning on its own and
# showing it invites pasting it somewhere it doesn't belong; the feed address
# is the thing a member actually needs.
class PrivateFeeds
  Feed = Struct.new(:title, :url, :kind, keyword_init: true)

  def self.for(member)
    new(member).all
  end

  def initialize(member)
    @member = member
  end

  # Empty unless the member can actually read paid content — a free member has
  # nothing to subscribe to, and listing URLs that would 401 is worse than
  # listing none.
  def all
    return [] unless SiteFeature.members_enabled?
    return [] unless @member&.may_read_protected_media?

    main + named + podcasts + releases
  end

  private

  # The site's main feed, when there's paid writing in it. Its public version
  # cuts paid articles at their paywall; this one carries them whole.
  def main
    return [] unless any_paid_posts?

    [ Feed.new(title: "All posts", url: "/feed/private.xml?token=#{token}", kind: :feed) ]
  end

  # Feeds from feeds.yml, each at whichever URL is the members' one for it:
  #
  #   audience: paid  → the feed is gated at its own address already
  #   anything else   → a private copy at /feed/<name>/private.xml
  #
  # Listed only when the feed could actually contain paid writing, so a feed
  # filtered to free content doesn't add a URL that shows nothing different.
  def named
    FeedConfig.feed_names.filter_map do |name|
      config = FeedConfig.get(name).to_h
      title = config["title"].presence || name.titleize

      if FeedConfig.paid?(name)
        Feed.new(title: title, url: "/feed/#{name}.xml?token=#{token}", kind: :feed)
      elsif paid_posts_in?(config)
        Feed.new(title: title, url: "/feed/#{name}/private.xml?token=#{token}", kind: :feed)
      end
    end
  rescue StandardError
    []
  end

  def any_paid_posts?
    Post.feed_posts.any? { |post| post.audience == "paid" }
  end

  def paid_posts_in?(config)
    FeedContent.for(config, include_paid: true).any? { |post| post.audience == "paid" }
  rescue StandardError
    false
  end

  # Shows with something paid in them. A wholly free show has a public feed and
  # no need for a private one.
  def podcasts
    PodcastConfig.podcast_keys.filter_map do |key|
      next unless paid_episodes?("podcast", key)

      Feed.new(
        title: PodcastConfig.get(key).to_h["title"].presence || key,
        url:   "/podcast/#{key}/private.xml?token=#{token}",
        kind:  :podcast
      )
    end
  end

  # Releases that publish a feed at all, and have something paid on them.
  def releases
    ReleaseConfig.feed_keys.filter_map do |key|
      next unless paid_episodes?("music", key)

      Feed.new(
        title: ReleaseConfig.get(key).to_h["title"].presence || key,
        url:   "/music/#{key}/private.xml?token=#{token}",
        kind:  :release
      )
    end
  end

  # Resolved rather than the raw field: a track on a paid release carries no
  # audience of its own, and it's still paid.
  def paid_episodes?(post_type, key)
    field = post_type == "podcast" ? "podcast" : "release"

    Post
      .published
      .where("json_extract(metadata, '$.post_type') = ?", post_type)
      .where("json_extract(metadata, '$.#{field}') = ?", key)
      .any? { |post| post.audience == "paid" }
  end

  def token
    @member.media_token
  end
end
