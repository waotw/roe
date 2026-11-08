# A post's content layout drawn for places that aren't its page: the
# newsletter email and feed items. Same parts, same order, so the email and
# the feed carry what the post page shows — each part in a form that works
# there, and nothing twice.
#
#   mode :email         the newsletter. Title as the heading, date and author,
#                       a Listen or Watch link in place of the player (email
#                       can't play audio or video).
#   mode :feed          an RSS or Atom item's content. No title, date or author
#                       (the reader shows those from the item's own fields),
#                       and no feed links (the reader is already in the feed);
#                       the player is a link.
#   mode :podcast_feed  a podcast episode's show notes. As :feed, with no
#                       player: the audio is the enclosure.
#
# Links are plain: subscribe and feed links are <a> tags in a paragraph. The
# episode list and ⏮ ⏭ stay on the site.
class ContentLayout
  class Text
    include ERB::Util

    MODES = %i[email feed podcast_feed].freeze
    META_PARTS = %w[date author].freeze

    def initialize(post, mode:, body_html:, layout: ContentLayout.for(post))
      raise ArgumentError, "unknown mode #{mode.inspect}" unless MODES.include?(mode)

      @post = post
      @mode = mode
      @body_html = body_html.to_s
      @layout = layout
      @body_check = BodyCheck.new(post)
    end

    def html
      @layout.rows.map(&:parts).filter_map do |names|
        parts = names.filter_map { |name| part(name).presence }
        next if parts.empty?
        next parts.first if names.length == 1

        if (names & META_PARTS).any?
          %(<div class="post-meta" style="color: #666; font-size: 0.875rem; margin-bottom: 2rem;">#{parts.join(" • ")}</div>)
        else
          %(<div class="layout-group">#{parts.join("\n")}</div>)
        end
      end.join("\n")
    end

    private

    def email? = @mode == :email

    def part(name)
      case name
      when "title"      then email? ? %(<h1>#{h(@post.title.presence || "Untitled")}</h1>) : ""
      when "subtitle"   then @post.subtitle.present? ? %(<p class="post-subtitle">#{h(@post.subtitle)}</p>) : ""
      when "date"       then email? ? date_html : ""
      when "author"     then email? ? author_html : ""
      when "image"      then image_html
      when "player"     then player_html
      when "body"       then email? ? %(<div class="post-content">\n#{@body_html}\n</div>) : @body_html
      when "feed_links" then email? ? links_paragraph("feed-links", feed_links) : ""
      when "subscribe"  then links_paragraph("podcast-subscribe", subscribe_links)
      when "excerpt"    then @post.excerpt.present? ? %(<p class="post-excerpt">#{h(@post.excerpt)}</p>) : ""
      when "tags"       then @post.tags.any? ? %(<p class="post-tags">#{h(@post.tags.join(", "))}</p>) : ""
      when *ContentLayout::BUILT_PARTS then "" # site-only: episodes, buy_button, …
      else field_html(name)
      end
    end

    def date_html
      date = @post.date
      date.respond_to?(:strftime) ? %(<span class="post-date">#{date.strftime("%B %d, %Y")}</span>) : ""
    end

    # An episode with no author of its own has its show's, as on its page.
    def author_html
      author = @post.metadata["author"].to_s.strip.presence
      if author.nil? && @post.post_type == "podcast" && (key = @post.metadata["podcast"].to_s.strip.presence)
        author = PodcastConfig.get(key)&.dig("author").to_s.strip.presence
      end
      author ? %(<span class="post-author">By #{h(author)}</span>) : ""
    end

    # The header image, when the post shows it on its page
    # (`image_in_header: true`), as one email- and feed-safe <img>.
    def image_html
      image = @post.metadata["image"].to_s.strip
      return "" if image.blank? || @post.metadata["image_in_header"].to_s != "true"

      picture = ResponsiveImageRenderer.render(image, alt: @post.title)
      NewsletterImageTransformer.transform(picture, site_url: site_url)
    end

    # Neither email nor a feed reader plays audio or video, so the player
    # becomes a way to it: a YouTube video's thumbnail linking to it, or a
    # link to the post. A podcast feed carries the audio itself, so nothing.
    #
    # The body's own player card can't play there either, so a player in the
    # body doesn't stand in for this one here.
    def player_html
      return "" if @mode == :podcast_feed

      if (embed = VideoEmbed.for(@post.video))
        return embed.link_html(label: @post.title).to_s
      end

      kind = @post.template_player_kind
      return "" unless kind

      label = kind == :video ? "Watch" : "Listen"
      %(<p class="player-link"><a href="#{h(absolute(@post.public_url))}">#{label}</a></p>)
    end

    # The post's public feed: the show's, the release's, or the site's. The
    # paid feeds belong to one member, so they stay on the site.
    def feed_links
      case @post.post_type
      when "podcast"
        key = @post.metadata["podcast"].to_s.strip
        key.present? && PodcastConfig.public_feed?(key) ? [ [ "RSS", "/podcast/#{key}.xml" ] ] : []
      when "music"
        key = @post.metadata["release"].to_s.strip
        key.present? && ReleaseConfig.feed_enabled?(key) && !ReleaseFeed.new(key).paid? ? [ [ "RSS", "/music/#{key}.xml" ] ] : []
      when "article", "newsletter"
        [ [ "RSS", "/feed.xml" ] ]
      else
        []
      end
    end

    def subscribe_links
      key = @post.metadata["podcast"].to_s.strip
      return [] if key.blank?

      links = PodcastConfig.subscribe_links(PodcastConfig.get(key)).map { |link| [ link[:label], link[:url] ] }
      links << [ "RSS Feed", "/podcast/#{key}.xml" ] if PodcastConfig.public_feed?(key)
      links
    end

    def links_paragraph(css_class, links)
      return "" if links.empty?

      anchors = links.map { |label, url| %(<a href="#{h(absolute(url))}">#{h(label)}</a>) }
      %(<p class="#{css_class}">#{anchors.join(" · ")}</p>)
    end

    def field_html(name)
      value = @post.metadata[name]
      value = value.join(", ") if value.is_a?(Array)
      return "" if value.blank? || value.is_a?(Hash)

      %(<p class="post-field post-#{name.dasherize}">#{h(value.to_s)}</p>)
    end

    def absolute(path)
      path.to_s.start_with?("/") ? "#{site_url}#{path}" : path.to_s
    end

    def site_url
      @site_url ||= (SiteConfig.get("url").presence || "http://localhost:3000").to_s.sub(%r{/+\z}, "")
    end
  end
end
