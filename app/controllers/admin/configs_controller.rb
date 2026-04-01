class Admin::ConfigsController < ApplicationController
  layout 'application'

  # Site Config Schema Definition
  SITE_CONFIG_SCHEMA = {
    site_info: {
      label: "Site Information",
      fields: {
        'title' => {
          type: :text,
          label: 'Site Title',
          required: true,
          hint: 'Used in page titles, feeds, and site header'
        },
        'description' => {
          type: :textarea,
          label: 'Site Description',
          rows: 3,
          hint: 'Used in meta tags and RSS/Atom feeds'
        },
        'author' => {
          type: :text,
          label: 'Author Name',
          hint: 'Default author for posts and pages'
        }
      }
    },

    branding: {
      label: "Branding",
      fields: {
        'logo' => {
          type: :text,
          label: 'Logo Image Path',
          hint: 'Copy logo url from Global Images.'
        },
        'logo_style' => {
          type: :select,
          label: 'Logo Style',
          options: [ 'beside_text', 'replace_text' ],
          depends_on: "logo",
          hint: "How the logo should be displayed"
        },
        'favicon' => {
          type: :text,
          label: 'Favicon',
          hint: 'Copy logo url from Global Images.',
          placeholder: "favicon.ico"
        }
      }
    },

    theme: {
      label: "Theme",
      fields: {
        'active' => {
          type: :select,
          label: 'Active Theme',
          options: ['egg', 'default'],
          hint: 'Select the theme for your site'
        }
      }
    },

    static_generation: {
      label: "Static Site Generation",
      fields: {
        'static_generation_enabled' => {
          type: :checkbox,
          label: 'Enable Auto-Generation',
          hint: 'Automatically generate static files when content changes'
        }
      }
    },

    fonts: {
      label: "Custom Fonts",
      help_text: "Upload font files with the Fonts button and copy url…",
      type: :font_roles,
      # Fixed roles with flexible variants
      roles: {
        heading: {
          label: "Heading Font",
          description: "Used for all headings (h1-h6)",
          required_variants: [ 'family', 'regular' ],
          common_variants: [ 'bold', 'italic', 'bold_italic', 'light', 'medium', 'semibold', 'black' ]
        },
        body: {
          label: "Body Font",
          description: "Used for paragraphs and body text",
          required_variants: [ 'family', 'regular' ],
          common_variants: [ 'bold', 'italic', 'bold_italic', 'light', 'medium', 'semibold' ]
        },
        mono: {
          label: "Monospace Font",
          description: "Used for code blocks and preformatted text",
          required_variants: [ 'family', 'regular' ],
          common_variants: [ 'bold', 'italic', 'bold_italic' ]
        }
      }
    }
  }.freeze

  def itunes_subcategories
    {
      'Arts' => ['Books', 'Design', 'Fashion & Beauty', 'Food', 'Performing Arts', 'Visual Arts'],
      'Business' => ['Careers', 'Entrepreneurship', 'Investing', 'Management', 'Marketing', 'Non-Profit'],
      'Comedy' => ['Comedy Interviews', 'Improv', 'Stand-Up'],
      'Education' => ['Courses', 'How To', 'Language Learning', 'Self-Improvement'],
      'Fiction' => ['Comedy Fiction', 'Drama', 'Science Fiction'],
      'Government' => [],  # ← Add these categories with empty arrays
      'Health & Fitness' => ['Alternative Health', 'Fitness', 'Medicine', 'Mental Health', 'Nutrition', 'Sexuality'],
      'History' => [],  # ← No subcategories
      'Kids & Family' => ['Education for Kids', 'Parenting', 'Pets & Animals', 'Stories for Kids'],
      'Leisure' => ['Animation & Manga', 'Automotive', 'Aviation', 'Crafts', 'Games', 'Hobbies', 'Home & Garden', 'Video Games'],
      'Music' => ['Music Commentary', 'Music History', 'Music Interviews'],
      'News' => ['Business News', 'Daily News', 'Entertainment News', 'News Commentary', 'Politics', 'Sports News', 'Tech News'],
      'Religion & Spirituality' => ['Buddhism', 'Christianity', 'Hinduism', 'Islam', 'Judaism', 'Religion', 'Spirituality'],
      'Science' => ['Astronomy', 'Chemistry', 'Earth Sciences', 'Life Sciences', 'Mathematics', 'Natural Sciences', 'Nature', 'Physics', 'Social Sciences'],
      'Society & Culture' => ['Documentary', 'Personal Journals', 'Philosophy', 'Places & Travel', 'Relationships'],
      'Sports' => ['Baseball', 'Basketball', 'Cricket', 'Fantasy Sports', 'Football', 'Golf', 'Hockey', 'Rugby', 'Running', 'Soccer', 'Swimming', 'Tennis', 'Volleyball', 'Wilderness', 'Wrestling'],
      'Technology' => [],  # ← No subcategories
      'True Crime' => [],  # ← No subcategories
      'TV & Film' => ['After Shows', 'Film History', 'Film Interviews', 'Film Reviews', 'TV Reviews']  # ← Was missing
    }
  end

  def index
    @config_files = [
      {
        section: "📁 Site",
        files: [
          { name: "site.yml", path: admin_edit_site_config_path, description: "Global site & feed settings, logo, and fonts" }
        ]
      },
      {
        section: "📁 Defaults",
        files: [
          { name: "cards.yml", path: admin_edit_cards_config_path, description: "Global Card settings & templates" },
          { name: "collections.yml", path: admin_edit_collections_config_path, description: "Global Collection settings & template" }
        ]
      }
    ]

    # Add podcast config to list if it exists
      if File.exist?(SiteConfig::DEFAULTS_PATH.join('podcast.yml'))
        @config_files[1][:files] << {
          name: "podcast.yml",
          path: admin_edit_podcast_config_path,
          description: "Global Podcast & feed settings"
        }
      end
  end

  def edit_site
    @config_type = 'site'
    @config_content = File.read(SiteConfig::SITE_FILE)
    @config_schema = SITE_CONFIG_SCHEMA
    render :edit
  end

  def update_site
    update_config('site', SiteConfig::SITE_FILE)
  end

  def edit_podcast
    podcast_config_path = SiteConfig::DEFAULTS_PATH.join('podcast.yml')

    # Check if file exists
    unless File.exist?(podcast_config_path)
      # Clean up orphaned database record
      SiteConfig.find_by("file_path LIKE ?", "%podcast.yml")&.destroy

      flash[:alert] = "Podcast configuration doesn't exist. Click 'Add Podcast Config' to create one."
      redirect_to admin_configs_path and return
    end

    @config_type = 'podcast'
    @config_content = File.read(podcast_config_path)
    @config_hash = YAML.load(@config_content) || {}
    @field_options = build_field_options_for_podcast
    @itunes_subcategories = itunes_subcategories
    render :edit
  end

  def update_podcast
    update_config('defaults/podcast', SiteConfig::DEFAULTS_PATH.join('podcast.yml'))
  end

  def edit_cards
    @config_type = 'cards'
    @config_content = File.read(SiteConfig::DEFAULTS_PATH.join('cards.yml'))
    @config_hash = YAML.load(@config_content) || {}
    @field_options = build_field_options_for_cards
    render :edit
  end

  def update_cards
    update_config('defaults/cards', SiteConfig::DEFAULTS_PATH.join('cards.yml'))
  end

  def edit_collections
    @config_type = 'collections'
    @config_content = File.read(SiteConfig::DEFAULTS_PATH.join('collections.yml'))
    @config_hash = YAML.load(@config_content) || {}
    @field_options = build_field_options_for_collections
    render :edit
  end

  def update_collections
    update_config('defaults/collections', SiteConfig::DEFAULTS_PATH.join('collections.yml'))
  end

  def field_options_for(config_type, field_name)
    case [ config_type, field_name ]
    when [ "collections", "default_source" ]
      [ "posts", "pages", "documentation" ]
    when [ "collections", "default_post_type" ]
      [ "all" ] + Post::POST_TYPES.keys.map(&:to_s)
    when [ "collections", "default_order" ]
      [ "date", "date-asc", "title", "filename" ]
    when [ "collections", "default_template" ]
      [ "list", "compact", "links" ]
    when [ "collections", "items_per_page" ]
      [ "5", "10", "20", "25", "50", "100" ]
    when [ "cards", "default_style" ]
      [ "small", "large" ]
    else
      nil
    end
  end

  def generate_podcast
    if File.exist?(SiteConfig::DEFAULTS_PATH.join('podcast.yml'))
      flash[:alert] = "Podcast configuration already exists"
    else
      ConfigGenerator.generate_podcast
      SiteConfig.sync_from_file('defaults/podcast')
      flash[:notice] = "Podcast configuration created successfully"
    end

    redirect_to admin_configs_path
  end

  def delete_podcast
    file_path = SiteConfig::DEFAULTS_PATH.join('podcast.yml')

    # Delete file
    File.delete(file_path) if File.exist?(file_path)

    # Delete from database
    SiteConfig.find_by("file_path LIKE ?", "%podcast.yml")&.destroy

    # Clear cache
    SiteConfig.reload!('defaults/podcast')
    PodcastConfig.reload!

    flash[:notice] = "Podcast configuration deleted successfully"
    redirect_to admin_configs_path
  end

  private

  def build_field_options_for_podcast
    # Flatten all subcategories into one array (will be filtered by JS)
    all_subcategories = itunes_subcategories.values.flatten.sort

    base_options = {
      'type' => ['episodic', 'serial'],
      'category' => [
        '', # Blank option
        'Arts', 'Business', 'Comedy', 'Education', 'Fiction', 'Government',
        'Health & Fitness', 'History', 'Kids & Family', 'Leisure', 'Music',
        'News', 'Religion & Spirituality', 'Science', 'Society & Culture',
        'Sports', 'Technology', 'True Crime', 'TV & Film'
      ],
      'category_2' => [
        '',
        'Arts', 'Business', 'Comedy', 'Education', 'Fiction', 'Government',
        'Health & Fitness', 'History', 'Kids & Family', 'Leisure', 'Music',
        'News', 'Religion & Spirituality', 'Science', 'Society & Culture',
        'Sports', 'Technology', 'True Crime', 'TV & Film'
      ],
      # Note: subcategory/subcategory_2 are arrays, handled by JS
      'language' => ['en', 'es', 'fr', 'de', 'it', 'pt', 'ja', 'zh', 'ko', 'ru'],
      'explicit' => ['false', 'true'],
      'episode_type' => ['full', 'trailer', 'bonus']
    }

    # Build prefixed versions separately
    prefixed_options = {}
    config_hash = YAML.load(@config_content) || {}
    config_hash.keys.each do |podcast_key|
      base_options.each do |field, options|
        prefixed_options["#{podcast_key}.#{field}"] = options
      end
    end

    # Merge and return
    base_options.merge(prefixed_options)
  end

  def build_field_options_for_collections
    existing_post_types = Post.all.map(&:post_type).compact.uniq.sort

    {
      'default_source' => [ 'posts', 'pages', 'documentation' ],
      'default_post_type' => [ 'all' ] + existing_post_types,
      'default_order' => [ 'date', 'date-asc', 'title', 'filename' ],
      'default_template' => [ 'list', 'compact', 'links' ],
      'items_per_page' => [ '10', '20', '25', '50', '100' ]
    }
  end

  def build_field_options_for_cards
    {
      'post-link.default_style' => [ 'small', 'large' ],
      'pullquote.default_position' => [ 'center', 'left', 'right' ]
    }
  end

  def update_config(type, file_path)
    content = params[:content]

    # Validate YAML syntax
    begin
      YAML.load(content)
    rescue Psych::SyntaxError => e
      flash.now[:error] = "Invalid YAML syntax: #{e.message}"
      @config_type = type.split('/').last
      @config_content = content
      render :edit and return
    end

    # Write to file
    File.write(file_path, content)

    # Sync to database and clear cache
    SiteConfig.sync_from_file(type)

    config_name = type.split('/').last.capitalize
    flash[:notice] = "#{config_name} configuration updated successfully"

    # Dynamic redirect based on type
    config_key = type.split('/').last
    redirect_to send("admin_edit_#{config_key}_config_path")
  rescue => e
    flash.now[:error] = "Failed to update configuration: #{e.message}"
    @config_type = type.split('/').last
    @config_content = content
    render :edit
  end
end
