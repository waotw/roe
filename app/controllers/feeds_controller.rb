class FeedsController < ApplicationController
  skip_before_action :require_authentication

  def rss
    @posts = Post.feed_posts.order(Arel.sql("json_extract(metadata, '$.date') DESC")).limit(20)

    feed_xml = FeedGenerator.new(
      posts: @posts,
      format: :rss,
      site_config: site_config,
      show_paid_teasers: show_paid_content?
    ).generate

    response.headers["Content-Type"] = "application/rss+xml; charset=utf-8"
    render xml: feed_xml
  end

  def atom
    @posts = Post.feed_posts.order(Arel.sql("json_extract(metadata, '$.date') DESC")).limit(20)

    feed_xml = FeedGenerator.new(
      posts: @posts,
      format: :atom,
      site_config: site_config,
      show_paid_teasers: show_paid_content?
    ).generate

    response.headers["Content-Type"] = "application/atom+xml; charset=utf-8"
    render xml: feed_xml
  end

  # A named feed defined in feeds.yml — a collection query served as RSS/Atom.
  # Free feeds are public and exclude paid content; paid feeds are token-gated
  # (like the private podcast feed) and include everything.
  def named
    feed = FeedConfig.get(params[:name])
    return head :not_found unless feed

    if FeedConfig.paid?(params[:name])
      return unless authorize_paid_feed! # renders 401 and returns false if denied
      include_paid = true
    else
      include_paid = false
    end

    fmt = params[:atom] ? :atom : :rss
    feed_xml = FeedGenerator.new(
      posts: FeedContent.for(feed, include_paid: include_paid, show_paid_teasers: show_paid_content?),
      format: fmt,
      site_config: site_config,
      include_paid: include_paid,
      show_paid_teasers: show_paid_content?
    ).generate

    response.headers["Content-Type"] =
      fmt == :atom ? "application/atom+xml; charset=utf-8" : "application/rss+xml; charset=utf-8"
    render xml: feed_xml
  end

  # A member's copy of the main feed: the same posts, with paid articles in
  # full rather than cut at their paywall.
  #
  # Podcasts have had this since paid episodes existed; articles only had the
  # public half, so someone who'd paid still read previews in their reader.
  def private_rss
    return head :not_found unless SiteFeature.members_enabled?
    return head :unauthorized unless member_for_private_feed

    posts = Post.feed_posts.order(Arel.sql("json_extract(metadata, '$.date') DESC")).limit(20)
    render_private_feed(posts)
  end

  # The same, for a feed defined in feeds.yml. A feed that's already
  # `audience: paid` is gated at its own URL and doesn't need this.
  def private_named
    return head :not_found unless SiteFeature.members_enabled?

    feed = FeedConfig.get(params[:name])
    return head :not_found unless feed
    return head :unauthorized unless member_for_private_feed

    render_private_feed(FeedContent.for(feed, include_paid: true))
  end

  def podcast
    @podcast_key = params[:podcast_key]

    podcast_config = PodcastConfig.get(@podcast_key)
    unless podcast_config
      head :not_found
      return
    end

    # PodcastConfig.public_feed? is the single answer to "is there a public
    # feed" — the views that link to it ask the same thing.
    unless PodcastConfig.public_feed?(@podcast_key)
      head :not_found
      return
    end

    episodes = podcast_episodes(@podcast_key)
    show_paid_teasers = SiteConfig.feature("members", "everyone.show_paid_content") || false

    feed_xml = FeedGenerator.new(
      posts: episodes,
      format: :podcast,
      site_config: site_config,
      podcast_config: podcast_config,
      include_paid: false,
      show_paid_teasers: show_paid_teasers
    ).generate

    response.headers["Content-Type"] = "application/rss+xml; charset=utf-8"
    render xml: feed_xml
  end

  # A music release as a podcast-format feed. 404 unless the release exists
  # and its owner ticked the box — an unpublished feed shouldn't be guessable
  # by URL. Paid releases get the same treatment as paid shows: no public feed.
  def music_release
    feed = ReleaseFeed.new(params[:release_key])

    return head :not_found unless feed.exists? && feed.enabled?
    return head :not_found if feed.paid?

    feed_xml = FeedGenerator.new(
      posts: feed.tracks,
      format: :podcast,
      site_config: site_config,
      podcast_config: feed.feed_config,
      include_paid: false,
      show_paid_teasers: SiteConfig.feature("members", "everyone.show_paid_content") || false
    ).generate

    response.headers["Content-Type"] = "application/rss+xml; charset=utf-8"
    render xml: feed_xml
  end

  # The paid member's copy of a release feed: every track, with full audio.
  # A wholly-paid release has no public feed at all, so this is the only way to
  # get it — same arrangement as a paid podcast.
  def private_music_release
    feed = ReleaseFeed.new(params[:release_key])

    # Admins reach it without a token, for checking their own feed.
    member = nil
    unless authenticated?
      member = member_for_private_feed
      return head :unauthorized unless member
    end

    # The owner not having turned the feed on is a 404 whoever is asking —
    # there's no feed to be a private copy of.
    return head :not_found unless feed.exists? && feed.enabled?

    feed_xml = FeedGenerator.new(
      posts: feed.tracks,
      format: :podcast,
      site_config: site_config,
      podcast_config: feed.feed_config,
      include_paid: true,
      show_paid_teasers: false,
      media_token: member&.media_token
    ).generate

    response.headers["Content-Type"] = "application/rss+xml; charset=utf-8"
    render xml: feed_xml
  end

  def private_podcast
    @podcast_key = params[:podcast_key]

    # Admins can access private feeds directly without a token
    member = nil
    unless authenticated?
      member = member_for_private_feed
      return head :unauthorized unless member
    end

    podcast_config = PodcastConfig.get(@podcast_key)
    unless podcast_config
      head :not_found
      return
    end

    # Private feed includes all episodes (paid + free)
    episodes = podcast_episodes(@podcast_key)

    feed_xml = FeedGenerator.new(
      posts: episodes,
      format: :podcast,
      site_config: site_config,
      podcast_config: podcast_config,
      include_paid: true,
      show_paid_teasers: false,
      media_token: member&.media_token
    ).generate

    response.headers["Content-Type"] = "application/rss+xml; charset=utf-8"
    render xml: feed_xml
  end

  private

  # include_paid: the caller has already established who's asking.
  def render_private_feed(posts)
    fmt = params[:atom] ? :atom : :rss

    feed_xml = FeedGenerator.new(
      posts: posts,
      format: fmt,
      site_config: site_config,
      include_paid: true
    ).generate

    response.headers["Content-Type"] =
      fmt == :atom ? "application/atom+xml; charset=utf-8" : "application/rss+xml; charset=utf-8"
    render xml: feed_xml
  end

  # Whether a public feed may advertise paid posts as previews. The same
  # members.yml setting collections follow, so turning off marketing to
  # non-members turns it off everywhere at once.
  def show_paid_content?
    SiteConfig.feature("members", "everyone.show_paid_content") || false
  end

  # The paid, active member a private feed request belongs to, or nil.
  #
  # media_token only. access_token signs a member in, so accepting it here
  # would mean a feed URL — which travels through podcast apps, shared links
  # and logs — doubling as a credential for the account.
  #
  # Private feed URLs briefly carried access_token, and this accepted it for a
  # while so those subscriptions kept working. Removed: a reader whose feed
  # stops can copy the current URL from their account page, which is a smaller
  # cost than leaving the sign-in token working as a feed key.
  def member_for_private_feed
    token = params[:token].to_s.strip
    return nil if token.blank?

    member = Member.find_by(media_token: token)
    return nil unless member&.paid? && member&.active?

    member
  end

  # Token gate for a paid named feed, mirroring #private_podcast: admins pass
  # through; everyone else needs a paid, active member. Renders 401 and returns
  # false when denied.
  def authorize_paid_feed!
    return true if authenticated?

    unless member_for_private_feed
      head :unauthorized
      return false
    end

    true
  end

  def podcast_episodes(podcast_key)
    Post
      .published
      .where("json_extract(metadata, '$.post_type') = ?", "podcast")
      .where("json_extract(metadata, '$.podcast') = ?", podcast_key)
      .order(Arel.sql("json_extract(metadata, '$.date') DESC"))
  end

  def site_config
    {
      title: SiteConfig.get("title") || "My Blog",
      description: SiteConfig.get("description") || "Blog posts and updates",
      url: request.base_url,
      author: SiteConfig.get("author") || "Site Author"
    }
  end
end
