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
