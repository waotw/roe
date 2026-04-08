class NewsletterRenderer
  attr_reader :post

  def initialize(post)
    @post = post
  end

  # Main method: returns email-ready HTML string
  def render
    html = wrap_in_email_template(post_html)
    inline_css(html)
  end

  # Preview version (doesn't inline CSS, easier to debug)
  def preview
    wrap_in_email_template(post_html)
  end

  private

  # Convert post markdown to HTML
  def post_html
    post.to_html
  end

  def convert_action_text_attachments(html)
    return html if html.blank?

    doc = Nokogiri::HTML.fragment(html)

    doc.css('action-text-attachment[content-type="image"]').each do |attachment|
      url = attachment['url']
      caption = attachment['caption']

      # Create img tag
      img = doc.document.create_element('img')
      img['src'] = url
      img['alt'] = caption if caption.present?
      img['style'] = 'max-width: 100%; height: auto;'

      # Add caption if present
      if caption.present?
        figure = doc.document.create_element('figure')
        figure['style'] = 'margin: 1.5rem 0;'

        figcaption = doc.document.create_element('figcaption')
        figcaption['style'] = 'font-size: 0.875rem; color: #666; margin-top: 0.5rem; text-align: center;'
        figcaption.content = caption

        figure.add_child(img)
        figure.add_child(figcaption)
        attachment.replace(figure)
      else
        attachment.replace(img)
      end
    end

    doc.to_html
  end

  def convert_relative_urls(html)
    return html if html.blank?

    site_url = SiteConfig.current('site')&.config&.dig('url')

    # Fallback to localhost for dev if not set
    site_url ||= 'http://localhost:3000'

    # Remove trailing slash
    site_url = site_url.sub(/\/$/, '')

    doc = Nokogiri::HTML.fragment(html)

    # Convert image src
    doc.css('img[src^="/"]').each do |img|
      img['src'] = "#{site_url}#{img['src']}"
    end

    # Convert link href
    doc.css('a[href^="/"]').each do |link|
      link['href'] = "#{site_url}#{link['href']}"
    end

    doc.to_html
  end

  # Wrap post HTML in email template structure
  def wrap_in_email_template(content_html)
    # 1. Convert Action Text attachments to img tags
    content_html = convert_action_text_attachments(content_html)

    # 2. Convert relative URLs to absolute
    content_html = convert_relative_urls(content_html)

    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>#{post_title}</title>
        <style>
          #{theme_css}
        </style>
      </head>
      <body>
        <table width="100%" cellpadding="0" cellspacing="0" style="max-width: 600px; margin: 0 auto;">
          <tr>
            <td>
              #{email_header}

              <article>
                <h1>#{post_title}</h1>
                #{post_metadata_html}

                <div class="post-content">
                  #{content_html}
                </div>
              </article>

              #{email_footer}
            </td>
          </tr>
        </table>
      </body>
      </html>
    HTML
  end

  # Get CSS from active theme
  def theme_css
    theme_name = active_theme
    theme_css_path = Rails.root.join('site', 'themes', theme_name, "#{theme_name}.css")

    if File.exist?(theme_css_path)
      File.read(theme_css_path)
    else
      default_email_css
    end
  end

  # Inline CSS using Premailer
  def inline_css(html)
    premailer = Premailer.new(
      html,
      with_html_string: true,
      adapter: :nokogiri,
      input_encoding: 'UTF-8'
    )

    premailer.to_inline_css
  end

  # Email header (logo, etc)
  def email_header
    <<~HTML
      <header style="margin-bottom: 2rem; padding-bottom: 1rem; border-bottom: 1px solid #eee;">
        <h2 style="margin: 0;">#{site_title}</h2>
      </header>
    HTML
  end

  # Email footer (unsubscribe, etc)
  def email_footer
    <<~HTML
      <footer style="margin-top: 3rem; padding-top: 2rem; border-top: 1px solid #eee; font-size: 0.875rem; color: #666;">
        <p>You're receiving this because you're subscribed to #{site_title}.</p>
        <p>
          <a href="{{unsubscribe_url}}">Unsubscribe</a> |
          <a href="{{account_url}}">Manage your account</a>
        </p>
      </footer>
    HTML
  end

  # Post metadata (author, date, etc)
  def post_metadata_html
    parts = []

    parts << "By #{post.metadata['author']}" if post.metadata['author'].present?
    parts << format_date(post.metadata['date']) if post.metadata['date'].present?

    return "" if parts.empty?

    <<~HTML
      <div class="post-meta" style="color: #666; font-size: 0.875rem; margin-bottom: 2rem;">
        #{parts.join(" • ")}
      </div>
    HTML
  end

  # Helper methods to get data from metadata
  def post_title
    post.metadata['title'] || 'Untitled'
  end

  def site_title
    SiteConfig.get('title') || 'Newsletter'
  end

  def active_theme
    SiteConfig.get('theme.active') || 'default'
  end

  def format_date(date_value)
    return nil if date_value.blank?

    date = date_value.is_a?(Date) ? date_value : Date.parse(date_value.to_s)
    date.strftime("%B %d, %Y")
  rescue
    date_value.to_s
  end

  # Fallback CSS if theme doesn't have a stylesheet
  def default_email_css
    <<~CSS
      body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        line-height: 1.6;
        color: #333;
      }

      h1, h2, h3 {
        margin-top: 1.5em;
        margin-bottom: 0.5em;
        line-height: 1.2;
      }

      h1 { font-size: 2rem; }
      h2 { font-size: 1.5rem; }
      h3 { font-size: 1.25rem; }

      p { margin-bottom: 1rem; }

      a { color: #0066cc; }

      img {
        max-width: 100%;
        height: auto;
      }

      pre {
        background: #f5f5f5;
        padding: 1rem;
        overflow-x: auto;
      }

      code {
        background: #f5f5f5;
        padding: 0.2em 0.4em;
        border-radius: 3px;
      }

      /* Hide default footnote list numbers (we have custom backlink numbers) */
      .footnotes ol {
        list-style: none;
        padding-left: 0;
      }

      .footnotes li {
        margin-bottom: 0.5rem;
      }

      .footnote-backlink-number {
        font-weight: bold;
        text-decoration: none;
        margin-right: 0.5rem;
      }
    CSS
  end
end
