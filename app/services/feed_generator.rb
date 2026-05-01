class FeedGenerator
  attr_reader :posts, :format, :site_config, :podcast_config, :include_paid, :show_paid_teasers

  def initialize(posts:, format: :rss, site_config: {}, podcast_config: nil, include_paid: false, show_paid_teasers: false)
    @posts = posts
    @format = format.to_sym
    @site_config = default_site_config.merge(site_config)
    @podcast_config = podcast_config
    @include_paid = include_paid
    @show_paid_teasers = show_paid_teasers
  end

  def generate
    case format
    when :rss
      generate_rss
    when :atom
      generate_atom
    when :podcast
      generate_podcast_rss
    else
      raise ArgumentError, "Unsupported format: #{format}"
    end
  end

  def generate_rss
    require 'rss'

    rss = RSS::Maker.make("2.0") do |maker|
      maker.channel.title = site_config[:title]
      maker.channel.link = site_config[:url]
      maker.channel.description = site_config[:description]
      maker.channel.updated = posts.first&.date&.to_time || Time.now
      maker.channel.managingEditor = site_config[:author] if site_config[:author].present?

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

  def filtered_episodes
    posts.select do |post|
      if post.audience == 'paid'
        # Include paid episodes when:
        #   - include_paid: rendering the private/full feed
        #   - show_paid_teasers: public feed where the site has opted to
        #     advertise paid episodes (title + excerpt + "subscribers only"
        #     blurb, no audio enclosure — handled in the item loop below)
        include_paid || show_paid_teasers
      else
        true
      end
    end
  end

  def generate_podcast_rss
    require 'nokogiri'

    builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
      xml.rss('version' => '2.0',
              'xmlns:itunes' => 'http://www.itunes.com/dtds/podcast-1.0.dtd',
              'xmlns:content' => 'http://purl.org/rss/1.0/modules/content/') do
        xml.channel do
          # Standard RSS elements
          xml.title podcast_config['title']
          xml.link podcast_config['link'] || site_config[:url]
          xml.language podcast_config['language'] || 'en'
          xml.copyright podcast_config['copyright'] || "© #{Time.now.year} #{podcast_config['author']}"
          xml.description podcast_config['description']
          xml.lastBuildDate (posts.first&.date&.to_time || Time.now).rfc822

          # iTunes channel elements
          xml['itunes'].author podcast_config['author']
          xml['itunes'].summary podcast_config['description']
          xml['itunes'].explicit(podcast_config['explicit'] ? 'true' : 'false')
          xml['itunes'].type(podcast_config['type'] || 'episodic')

          # iTunes owner
          xml['itunes'].owner do
            xml['itunes'].name podcast_config['owner_name'] || podcast_config['author']
            xml['itunes'].email podcast_config['email']
          end

          # iTunes artwork
          if podcast_config['artwork'].present?
            artwork_url = image_full_url(podcast_config['artwork'])
            xml['itunes'].image(href: artwork_url)
            xml.image do
              xml.url artwork_url
              xml.title podcast_config['title']
              xml.link podcast_config['link'] || site_config[:url]
            end
          end

          # iTunes categories
          add_itunes_categories_xml(xml, podcast_config)

          # Episodes
          filtered_episodes.each do |post|
            is_paid = post.audience == 'paid'

            xml.item do
              xml.title post.title
              xml.link "#{site_config[:url]}/posts/#{post.url_name}"

              # For paid episodes in public feed (teasers): show excerpt only, no audio
              xml.description do
                if is_paid && show_paid_teasers
                  xml.cdata "<p><em>This episode is for paid subscribers only.</em></p>#{episode_summary(post)}"
                else
                  xml.cdata episode_content_html(post)
                end
              end

              xml.pubDate post.date.to_time.rfc822 if post.date

              # Immutable GUID
              xml.guid(post.metadata['guid'], isPermaLink: 'false')

              # Audio enclosure — omit for paid episodes in public feed
              if post.metadata['audio'].present? && (!is_paid || include_paid)
                audio_url = audio_full_url(post.metadata['audio'])
                audio_path = audio_file_path(post.metadata['audio'])

                xml.enclosure(
                  url: audio_url,
                  length: audio_file_size(audio_path),
                  type: audio_mime_type(audio_path)
                )
              end

              # iTunes episode elements
              xml['itunes'].title post.title
              xml['itunes'].author post.metadata['author'] || podcast_config['author']

              # Summary: excerpt > subtitle > first sentence
              xml['itunes'].summary episode_summary(post)

              xml['itunes'].duration post.metadata['duration'] if post.metadata['duration'].present?
              xml['itunes'].explicit(post.metadata['explicit'] == true ? 'true' : 'false')
              xml['itunes'].episode post.metadata['episode_number'] if post.metadata['episode_number'].present?
              xml['itunes'].season post.metadata['season'] if post.metadata['season'].present?
              xml['itunes'].episodeType post.metadata['episode_type'] || 'full'

              # Episode artwork (optional override)
              if post.metadata['image'].present?
                xml['itunes'].image(href: image_full_url(post.metadata['image']))
              end
            end
          end
        end
      end
    end

    builder.to_xml
  end

  private

  def default_site_config
    {
      title: SiteConfig.get('title').presence || "My Site",
      description: SiteConfig.get('description').presence || "Latest posts and updates",
      url: SiteConfig.site_url.presence || "https://example.com",
      author: SiteConfig.get('author_name').presence || SiteConfig.get('author_email').presence || "Site Author"
    }
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

  def add_itunes_categories_xml(xml, config)
    # Primary category
    if config['category'].present?
      xml['itunes'].category(text: config['category']) do
        # Subcategories (handle array format)
        if config['subcategory'].is_a?(Array)
          config['subcategory'].first(2).each do |subcat|
            xml['itunes'].category(text: subcat)
          end
        end
      end
    end

    # Secondary category (if your config supports it later)
    if config['category_secondary'].present?
      xml['itunes'].category(text: config['category_secondary']) do
        if config['subcategory_secondary'].is_a?(Array)
          config['subcategory_secondary'].first(2).each do |subcat|
            xml['itunes'].category(text: subcat)
          end
        end
      end
    end
  end

  def episode_description(post)
    # Priority: excerpt > subtitle > content snippet
    return post.excerpt if post.excerpt.present?
    return post.subtitle if post.subtitle.present?

    # Fallback: first paragraph or truncated content
    feed_description(post)
  end

  def audio_full_url(audio_path)
    # Remove leading slash if present
    clean_path = audio_path.start_with?('/') ? audio_path[1..-1] : audio_path
    "#{site_config[:url]}/#{clean_path}"
  end

  def image_full_url(image_path)
    clean_path = image_path.start_with?('/') ? image_path[1..-1] : image_path
    "#{site_config[:url]}/#{clean_path}"
  end

  def audio_file_path(audio_path)
    # Convert /media/audio/file.mp3 to absolute file path
    File.join(RoeSitePaths::SITE_PATH, audio_path.delete_prefix('/'))
  end

  def audio_file_size(file_path)
    File.exist?(file_path) ? File.size(file_path) : 0
  end

  def audio_mime_type(file_path)
    ext = File.extname(file_path).downcase
    case ext
    when '.mp3' then 'audio/mpeg'
    when '.m4a' then 'audio/x-m4a'
    when '.mp4' then 'audio/mp4'
    when '.wav' then 'audio/wav'
    when '.ogg' then 'audio/ogg'
    else 'audio/mpeg' # default
    end
  end

  def episode_summary(post)
    # Get the source text
    source = if post.excerpt.present?
      post.excerpt
    elsif post.subtitle.present?
      post.subtitle
    else
      # Extract first sentence from content
      return extract_first_sentence(post.content)
    end

    # Convert excerpt/subtitle markdown to plain text
    convert_markdown_to_plain(source)
  end

  def convert_markdown_to_plain(text)
    # Convert markdown to HTML, then strip tags
    html = Kramdown::Document.new(text, input: 'GFM').to_html
    ActionController::Base.helpers.strip_tags(html).squish.truncate(300)
  end

  def episode_content_html(post)
    # Convert full markdown content to HTML for show notes
    clean_content = post.content
      .gsub(/```card\r?\n.*?```/m, '')         # Remove card blocks
      .gsub(/```collection\r?\n.*?```/m, '')   # Remove collection blocks

    # Convert markdown to HTML
    Kramdown::Document.new(clean_content, input: 'GFM').to_html
  end

  def extract_first_sentence(content)
    # Clean content
    clean_content = content
      .gsub(/```card\r?\n.*?```/m, '')
      .gsub(/```collection\r?\n.*?```/m, '')

    # Convert to plain text
    html = Kramdown::Document.new(clean_content, input: 'GFM').to_html
    text = ActionController::Base.helpers.strip_tags(html).squish

    # Extract first sentence
    match = text.match(/^[^.!?]+[.!?]/)
    match ? match[0].strip : text.truncate(200)
  end
end
