class ConfigGenerator
  SYSTEM_PATH = Rails.root.join('site', 'system')
  DEFAULTS_PATH = SYSTEM_PATH.join('defaults')
  ASSETS_PATH = SYSTEM_PATH.join('assets')

  def self.generate_all
    new.generate_all
  end

  def self.generate_podcast
    new.generate_podcast_defaults
  end

  def generate_all
    ensure_directories
    generate_site_config unless File.exist?(SYSTEM_PATH.join('site.yml'))
    generate_cards_defaults unless File.exist?(DEFAULTS_PATH.join('cards.yml'))
    generate_collections_defaults unless File.exist?(DEFAULTS_PATH.join('collections.yml'))
  end

  def generate_podcast_defaults
    content = <<~YAML
      # Podcast Configuration
      # Define one or more podcast feeds for your site

      my-podcast:
        title: "My Podcast"
        description: "A podcast about things"
        author: "Your Name"
        email: "you@example.com"
        category: "Technology"
        subcategory: ""
        language: "en"
        copyright: "2026 Your Name"
        explicit: false
        type: "episodic"
        artwork: ""
        link: "https://yoursite.com"
    YAML

    File.write(DEFAULTS_PATH.join('podcast.yml'), content)
    puts "✓ Generated podcast.yml"
  end

  def self.generate_members
    new.generate_members_defaults
  end

  def generate_members_defaults(show_paid_content: true)
    content = <<~YAML
      non-members:
        show_paid_content: #{show_paid_content}
        show_paid_indicator: true

      members:
    YAML

    File.write(DEFAULTS_PATH.join('members.yml'), content)
    puts "✓ Generated members.yml"
  end

  private

  def ensure_directories
    FileUtils.mkdir_p(SYSTEM_PATH)
    FileUtils.mkdir_p(DEFAULTS_PATH)
    FileUtils.mkdir_p(ASSETS_PATH.join('fonts'))
    FileUtils.mkdir_p(ASSETS_PATH.join('images'))
  end

  def generate_site_config
    content = <<~YAML
      # Site Configuration
      # Basic metadata used throughout your site and in RSS/Atom feeds

      title: My Site
      description: A description of my site
      author: Your Name

      # Branding
      # logo: logo.svg
      # logo_style: beside_text  # Options: beside_text, replace_text
      # favicon: favicon.ico

      # ──────────────────────────────────────────────────────────────
      # Custom Fonts (optional)
      # Upload font files to site/system/assets/fonts/
      # Supported formats: woff2 (recommended), woff, ttf
      #
      # Available variants for each font role:
      #   - regular (required)
      #   - bold (optional)
      #   - italic (optional)
      #   - bold_italic (optional)
      #
      # If variants aren't specified, the browser will synthesize them from regular.

      # fonts:
      #   heading:
      #     family: "Custom Heading"
      #     regular: heading-regular.woff2
      #     bold: heading-bold.woff2
      #
      #   body:
      #     family: "Custom Body"
      #     regular: body-regular.woff2
      #     bold: body-bold.woff2
      #     italic: body-italic.woff2
      #     bold_italic: body-bold-italic.woff2
      #
      #   mono:
      #     family: "Custom Mono"
      #     regular: mono-regular.woff2
    YAML

    File.write(SYSTEM_PATH.join('site.yml'), content)
    puts "✓ Generated site.yml"
  end

  def generate_cards_defaults
    content = <<~YAML
      # Card Defaults Configuration

      post-link:
        default_image: /media/images/default-post.jpg
        default_style: small
        default_link_text: "Read full story →"

      aside:
        default_link_text: "→"

      # Button templates - used when inserting cards via editor buttons

      aside_button_template: |-
        type: aside
        text: __PLACEHOLDER__
        link:
        link_text:
        image:

      post_link_button_template: |-
        type: post-link
        style: small
        post:

      pullquote_button_template: |-
        type: pullquote
        text: __PLACEHOLDER__
    YAML

    File.write(DEFAULTS_PATH.join('cards.yml'), content)
    puts "✓ Generated cards.yml"
  end

  def generate_collections_defaults
    content = <<~YAML
      default_source: posts
      default_post_type: all
      default_order: date
      default_limit: 10
      default_template: list
      show_paid_content: false

      button_template: |-
        heading: __PLACEHOLDER__
        limit: 5
        post_type: all
        template: list
    YAML

    File.write(DEFAULTS_PATH.join('collections.yml'), content)
    puts "✓ Generated collections.yml"
  end
end
