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
        'url' => {  # ← ADD THIS
          type: :text,
          label: 'Site URL',
          required: true,
          hint: 'Full URL of your site (e.g., https://example.com) - used in emails and feeds',
          placeholder: 'https://example.com'
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
        },
        'author_email' => {
          type: :text,
          label: 'Author Email',
          hint: 'Email address of the site author'
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

    defaults_files = [
      { name: "cards.yml", path: admin_edit_cards_config_path, description: "Global Card settings & templates" },
      { name: "collections.yml", path: admin_edit_collections_config_path, description: "Global Collection settings & template" }
    ]

    # Add members config if it exists
    if File.exist?(SiteConfig::DEFAULTS_PATH.join('members.yml'))
      defaults_files << {
        name: "members.yml",
        path: admin_edit_members_config_path,
        description: "Membership & paid content settings"
      }
    end

    # Add podcast config if it exists
    if File.exist?(SiteConfig::DEFAULTS_PATH.join('podcast.yml'))
      defaults_files << {
        name: "podcast.yml",
        path: admin_edit_podcast_config_path,
        description: "Global Podcast & feed settings"
      }
    end

    @config_files[1][:files] = defaults_files
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

  def edit_members
    members_config_path = SiteConfig::DEFAULTS_PATH.join('members.yml')

    unless File.exist?(members_config_path)
      flash[:alert] = "Members configuration doesn't exist."
      redirect_to admin_configs_path and return
    end

    @config_type = 'members'
    @config_content = File.read(members_config_path)
    @config_hash = YAML.load(@config_content) || {}
    @field_options = build_field_options_for_members
    @field_hints = build_field_hints_for_members  # ← Add this

    render :edit
  end

  def update_members
    update_config('defaults/members', SiteConfig::DEFAULTS_PATH.join('members.yml'))
  end

  def new_members_setup
    if File.exist?(SiteConfig::DEFAULTS_PATH.join('members.yml'))
      flash[:alert] = "Members configuration already exists"
      redirect_to admin_configs_path
    else
      render :new_members_modal
    end
  end

  def create_members
    show_paid = params[:show_paid_content] == 'true'

    ConfigGenerator.new.generate_members_defaults(show_paid_content: show_paid)
    SiteConfig.sync_from_file('defaults/members')

    # Sync the new upgrade page
    ContentSyncService.sync_all_pages

    flash[:notice] = "Members feature enabled successfully"
    redirect_to admin_configs_path
  end

  def delete_members
    file_path = SiteConfig::DEFAULTS_PATH.join('members.yml')

    File.delete(file_path) if File.exist?(file_path)
    SiteConfig.find_by("file_path LIKE ?", "%members.yml")&.destroy
    SiteConfig.reload!('defaults/members')

    flash[:notice] = "Members feature disabled successfully"
    redirect_to admin_configs_path
  end

  private

  def sync_stripe_payments(members_config)
    payments_config = members_config&.dig('payments')

    # If payments not configured or not enabled, just return success
    unless payments_config && (payments_config['enabled'] == true || payments_config['enabled'] == 'true')
      return { success: true, message: "Members configuration updated successfully" }
    end

    # Check if Stripe is connected
    stripe_config = StripeConfig.current
    unless stripe_config.connected?
      return { success: false, message: "Members configuration updated but Stripe not connected" }
    end

    # Sync product/price with Stripe
    manager = StripeProductManager.new
    if manager.sync_from_config(payments_config)
      { success: true, message: "Members configuration updated and Stripe synced (price: #{payments_config['price']})" }
    else
      { success: false, message: "Members configuration updated but Stripe sync failed: #{manager.errors.join(', ')}" }
    end
  end

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

  def build_field_options_for_members
    {
      'non-members.show_paid_content' => ['true', 'false'],
      'non-members.show_paid_indicator' => ['true', 'false'],
      'payments.enabled' => ['false', 'true'],
      'newsletter.enabled' => ['false', 'true']
    }
  end

  def build_field_hints_for_members
    # Get currency from Stripe if connected
    stripe_config = StripeConfig.current
    currency = stripe_config.connected? ? stripe_config.default_currency.upcase : 'USD'

    {
      'payments.enabled' => 'Turn on paid memberships (requires connection to your Stripe account)',
      'payments.price' => "One-time payment amount in #{currency} (e.g., 49.00)",
      'newsletter.enabled' => 'Enable newsletter sending via Postmark (requires Postmark account & configuration)'
    }
  end

  def update_config(type, file_path)
    content = params[:content]

    # Load old config to compare (only for site config)
    old_config = nil
    if type == 'site' && File.exist?(file_path)
      old_config = YAML.load_file(file_path) rescue {}
    end

    # Validate YAML syntax
    begin
      new_config = YAML.load(content)
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

    # Handle different config types
    case type
    when 'site'
      Rails.cache.clear

      # Auto-generate when enabling static mode
      if old_config && !old_config['static_generation_enabled'] && new_config['static_generation_enabled']
        StaticGenerator.new.generate_all
        flash[:notice] = "Site configuration updated and static site generated successfully"
      else
        flash[:notice] = "Site configuration updated successfully"
      end

    when 'defaults/members'
      Rails.cache.clear

      # Sync Stripe product/price if payments are enabled
      sync_result = sync_stripe_payments(new_config)

      # Regenerate collections if static mode is enabled
      if SiteConfig.current('site')&.static_generation_enabled
        StaticGenerator.new.generate_all
        flash[:notice] = sync_result[:message] + " and static site regenerated"
      else
        flash[:notice] = sync_result[:message]
      end

    else
      flash[:notice] = "#{type.split('/').last.capitalize} configuration updated successfully"
    end

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
