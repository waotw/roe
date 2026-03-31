class ConfigGenerator
  SYSTEM_PATH = Rails.root.join('site', 'system')
  DEFAULTS_PATH = SYSTEM_PATH.join('defaults')
  ASSETS_PATH = SYSTEM_PATH.join('assets')

  def self.generate_all
    new.generate_all
  end

  def generate_all
    ensure_directories
    generate_site_config unless File.exist?(SYSTEM_PATH.join('site.yml'))
    generate_cards_defaults unless File.exist?(DEFAULTS_PATH.join('cards.yml'))
    generate_collections_defaults unless File.exist?(DEFAULTS_PATH.join('collections.yml'))
    generate_podcast_defaults unless File.exist?(DEFAULTS_PATH.join('podcast.yml'))
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
      # Collections Default Configuration
      # These values are used when a collection doesn't specify these parameters

      # Default source for collections
      # Options: posts, pages, documentation
      default_source: posts

      # Default post type to display (only applies when source is 'posts')
      # Options: all, article, music, video, note, link
      # Use 'all' to show all post types
      default_post_type: all

      # Default ordering method
      # Options:
      #   - date: Sort by date (newest first)
      #   - date-asc: Sort by date (oldest first)
      #   - title: Sort alphabetically by title
      #   - filename: Sort by filename
      default_order: date

      # Default number of items to show
      # Set to a number (e.g., 10) or use 'all' to show everything
      default_limit: 10

      # Default template for displaying collections
      # Options:
      #   - list: Simple list of titles with links
      #   - compact: Condensed view with minimal spacing
      #   - full: Full view with excerpts and metadata
      default_template: list

      # Button template - used when inserting a new collection via editor button
      button_template: |-
        heading:
        limit: 5
        post_type:
        template: list
    YAML

    File.write(DEFAULTS_PATH.join('collections.yml'), content)
    puts "✓ Generated collections.yml"
  end
end
