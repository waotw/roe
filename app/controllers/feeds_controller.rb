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
