class FeedsController < ApplicationController
  skip_before_action :require_authentication

  def rss
    @posts = Post.feed_posts.order(Arel.sql("json_extract(metadata, '$.date') DESC")).limit(20)

    feed_xml = FeedGenerator.new(
      posts: @posts,
      format: :rss,
      site_config: site_config
    ).generate

    response.headers['Content-Type'] = 'application/rss+xml; charset=utf-8'
    render xml: feed_xml
  end

  def atom
    @posts = Post.feed_posts.order(Arel.sql("json_extract(metadata, '$.date') DESC")).limit(20)

    feed_xml = FeedGenerator.new(
      posts: @posts,
      format: :atom,
      site_config: site_config
    ).generate

    response.headers['Content-Type'] = 'application/atom+xml; charset=utf-8'
    render xml: feed_xml
  end

  def podcast
    @podcast_key = params[:podcast_key]

    # Validate podcast exists in config
    podcast_config = PodcastConfig.get(@podcast_key)
    unless podcast_config
      head :not_found
      return
    end

    # Get published podcast episodes for this show
    @episodes = Post
      .published
      .where("json_extract(metadata, '$.post_type') = ?", 'podcast')
      .where("json_extract(metadata, '$.podcast') = ?", @podcast_key)
      .order(Arel.sql("json_extract(metadata, '$.date') DESC"))

    feed_xml = FeedGenerator.new(
      posts: @episodes,
      format: :podcast,
      site_config: site_config,
      podcast_config: podcast_config
    ).generate

    response.headers['Content-Type'] = 'application/rss+xml; charset=utf-8'
    render xml: feed_xml
  end

  private

  def site_config
    {
      title: SiteConfig.get('title') || "My Blog",
      description: SiteConfig.get('description') || "Blog posts and updates",
      url: request.base_url,
      author: SiteConfig.get('author') || "Site Author"
    }
  end
end
