class FeedsController < ApplicationController
  skip_before_action :require_authentication

  def rss
    @posts = Post.feed_posts.order(Arel.sql("json_extract(metadata, '$.date') DESC")).limit(20)

    feed_xml = FeedGenerator.new(
      posts: @posts,
      format: :rss,
      site_config: site_config
    ).generate

    response.headers["Content-Type"] = "application/rss+xml; charset=utf-8"
    render xml: feed_xml
  end

  def atom
    @posts = Post.feed_posts.order(Arel.sql("json_extract(metadata, '$.date') DESC")).limit(20)

    feed_xml = FeedGenerator.new(
      posts: @posts,
      format: :atom,
      site_config: site_config
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
      posts: FeedContent.for(feed, include_paid: include_paid),
      format: fmt,
      site_config: site_config
    ).generate

    response.headers["Content-Type"] =
      fmt == :atom ? "application/atom+xml; charset=utf-8" : "application/rss+xml; charset=utf-8"
    render xml: feed_xml
  end

  def podcast
    @podcast_key = params[:podcast_key]

    podcast_config = PodcastConfig.get(@podcast_key)
    unless podcast_config
      head :not_found
      return
    end

    # If the whole podcast is paid-only, no public feed exists
    if podcast_config["audience"] == "paid"
      head :not_found
      return
    end

    # Get all published episodes for this podcast
    episodes = podcast_episodes(@podcast_key)

    # Check members.yml for whether to tease paid episode titles/descriptions
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
    unless authenticated?
      member = Member.find_by(access_token: params[:token].to_s.presence)
      return head :unauthorized unless member&.paid? && member&.active?
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
      show_paid_teasers: false
    ).generate

    response.headers["Content-Type"] = "application/rss+xml; charset=utf-8"
    render xml: feed_xml
  end

  def private_podcast
    @podcast_key = params[:podcast_key]

    # Admins can access private feeds directly without a token
    unless authenticated?
      token = params[:token]

      # Token is required for non-admins
      unless token.present?
        head :unauthorized
        return
      end

      # Look up member by token
      member = Member.find_by(access_token: token)
      unless member&.paid? && member&.active?
        head :unauthorized
        return
      end
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
      show_paid_teasers: false
    ).generate

    response.headers["Content-Type"] = "application/rss+xml; charset=utf-8"
    render xml: feed_xml
  end

  private

  # Token gate for a paid feed, mirroring #private_podcast: admins pass through;
  # everyone else needs a paid, active member's access token. Renders 401 and
  # returns false when denied.
  def authorize_paid_feed!
    return true if authenticated?

    token = params[:token]
    if token.blank?
      head :unauthorized
      return false
    end

    member = Member.find_by(access_token: token)
    unless member&.paid? && member&.active?
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
