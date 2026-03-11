class FeedGenerator
  attr_reader :posts, :format, :site_config

  def initialize(posts:, format: :rss, site_config: {})
    @posts = posts
    @format = format.to_sym
    @site_config = default_site_config.merge(site_config)
  end

  def generate
    case format
    when :rss
      generate_rss
    when :atom
      generate_atom
    else
      raise ArgumentError, "Unsupported format: #{format}"
    end
  end

  private

  def default_site_config
    {
      title: "My Blog",
      description: "Blog posts and updates",
      url: "http://localhost:3000",
      author: "Site Author"
    }
  end

  def generate_rss
    require 'rss'

    rss = RSS::Maker.make("2.0") do |maker|
      maker.channel.title = site_config[:title]
      maker.channel.link = site_config[:url]
      maker.channel.description = site_config[:description]
      maker.channel.updated = posts.first&.date&.to_time || Time.now

      posts.each do |post|
        maker.items.new_item do |item|
          item.title = post.title
          item.link = "#{site_config[:url]}/posts/#{post.url_name}"

          item.description = if post.excerpt.present?
            post.excerpt
          else
            feed_description(post)
          end

          item.pubDate = post.date.to_time if post.date
          item.author = post.author if post.author
          item.guid.content = "#{site_config[:url]}/posts/#{post.url_name}"
          item.guid.isPermaLink = true
        end
      end
    end

    rss.to_s
  end

  def generate_atom
    require 'rss'

    feed = RSS::Maker.make("atom") do |maker|
      maker.channel.title = site_config[:title]
      maker.channel.link = site_config[:url]
      maker.channel.description = site_config[:description]
      maker.channel.updated = posts.first&.date&.to_time || Time.now
      maker.channel.author = site_config[:author]
      maker.channel.id = site_config[:url]

      posts.each do |post|
        maker.items.new_item do |item|
          item.title = post.title
          item.link = "#{site_config[:url]}/posts/#{post.url_name}"

          item.description = if post.excerpt.present?
            post.excerpt
          else
            feed_description(post)
          end

          item.updated = post.date.to_time if post.date
          item.author = post.author if post.author
          item.id = "#{site_config[:url]}/posts/#{post.url_name}"
        end
      end
    end

    feed.to_s
  end

  def feed_description(post)
    # Priority: subtitle > excerpt > first paragraph
    return post.subtitle if post.subtitle.present?
    return post.excerpt if post.excerpt.present?

    # Extract first paragraph from content
    clean_content = post.content
      .gsub(/```card\r?\n.*?```/m, '') # Remove card blocks
      .gsub(/```collection\r?\n.*?```/m, '') # Remove collection blocks

    # Convert to HTML
    html = Kramdown::Document.new(clean_content, input: 'GFM').to_html

    # Extract first <p> tag content
    doc = Nokogiri::HTML.fragment(html)
    first_paragraph = doc.css('p').first&.text

    if first_paragraph.present?
      first_paragraph.squish.truncate(200)
    else
      # Fallback: strip all tags and truncate
      ActionController::Base.helpers.strip_tags(html).squish.truncate(200)
    end
  end
end
