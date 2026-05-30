class EmailRenderer
  def self.render(template_name, variables = {})
    template_path = File.join(RoeSitePaths::SITE_PATH, "emails", "#{template_name}.md")

    unless File.exist?(template_path)
      raise "Email template not found: #{template_name}"
    end

    content = File.read(template_path)

    # Replace @variables with actual values
    variables.each do |key, value|
      content.gsub!("@#{key}", value.to_s)
    end

    # Convert markdown to HTML
    html = Kramdown::Document.new(content).to_html

    # Wrap in basic email styling
    wrap_in_email_layout(html)
  end

  def self.render_content(content)
    # Convert markdown to HTML
    html = Kramdown::Document.new(content).to_html

    # Wrap in basic email styling
    wrap_in_email_layout(html)
  end

  private

  def self.wrap_in_email_layout(html)
    styles = email_styles

    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <style>
          body {
            font-family: #{styles[:font_body]};
            line-height: 1.6;
            color: #{styles[:color_text]};
            max-width: 600px;
            margin: 0 auto;
            padding: 20px;
          }
          a { color: #{styles[:color_primary]}; text-decoration: none; }
          a:hover { text-decoration: underline; }
          h1 {
            font-family: #{styles[:font_heading]};
            font-size: 24px;
            margin-bottom: 20px;
          }
          hr { border: none; border-top: 1px solid #e5e7eb; margin: 30px 0; }
        </style>
      </head>
      <body>
        #{html}
      </body>
      </html>
    HTML
  end

  def self.email_styles
    # Roe's theme system stores the active theme's files flat under
    # /site/theme/ (egg.css, checkout.js, optional email.yml). The
    # earlier `Rails.root.join('themes', theme_name)` form pointed at a
    # path that never existed under either the current/ or versioned
    # layout, so this always silently fell through to defaults.
    email_yml = File.join(RoeSitePaths::SITE_PATH, "theme", "email.yml")

    if File.exist?(email_yml)
      YAML.load_file(email_yml).symbolize_keys
    else
      default_email_styles
    end
  end

  def self.default_email_styles
    {
      font_body: "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif",
      font_heading: "Georgia, serif",
      color_primary: "#2563eb",
      color_text: "#333"
    }
  end
end
