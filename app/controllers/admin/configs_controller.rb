class Admin::ConfigsController < Admin::BaseController
  # Site Config Schema Definition
  SITE_CONFIG_SCHEMA = {
    site_info: {
      label: "Site Information",
      fields: {
        "title" => {
          type: :text,
          label: "Site Title",
          required: true,
          hint: "Used in page titles, feeds, and site header"
        },
        "url" => {
          type: :text,
          label: "Site URL",
          required: true,
          hint: "Full URL of your site (e.g., https://example.com) - used in emails and feeds",
          placeholder: "https://example.com"
        },
        "description" => {
          type: :textarea,
          label: "Site Description",
          rows: 3,
          hint: "Used in meta tags and RSS/Atom feeds"
        },
        "author" => {
          type: :text,
          label: "Author Name",
          hint: "Default author for posts and pages"
        },
        "author_email" => {
          type: :text,
          label: "Author Email",
          hint: "Email address of the site author"
        }
      }
    },

    branding: {
      label: "Branding",
      fields: {
        "logo" => {
          type: :text,
          label: "Logo Image Path",
          hint: "Copy logo url from Global Images."
        },
        "logo_style" => {
          type: :select,
          label: "Logo Style",
          options: [ "beside_text", "replace_text" ],
          depends_on: "logo",
          hint: "How the logo should be displayed"
        },
        "favicon" => {
          type: :text,
          label: "Favicon",
          hint: "Copy logo url from Global Images.",
          placeholder: "favicon.ico"
        },
        "social_image" => {
          type: :text,
          label: "Social Image",
          hint: "Default image shown when your site is shared on social platforms (Facebook, X, LinkedIn, iMessage, Slack). Used as a fallback when a post or page has no `image:` of its own. Recommended size: 1200×630.",
          placeholder: "social-share.jpg"
        }
      }
    },

    theme: {
      label: "Theme",
      fields: {
        "active" => {
          type: :select,
          label: "Active Theme",
          options: [ "egg", "default" ],
          hint: "Select the theme for your site"
        }
      }
    },

    static_generation: {
      label: "Static Site Generation",
      fields: {
        "static_generation_enabled" => {
          type: :checkbox,
          label: "Enable Auto-Generation",
          hint: "Automatically generate static files when content changes"
        }
      }
    }
  }.freeze

  FONTS_CONFIG_SCHEMA = {
    themes: {
      label: "Themes",
      help_text: "Themes that should load these fonts. Leave all unchecked to load for every theme.",
      type: :theme_multi_select
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
          required_variants: [ "family", "regular" ],
          common_variants: [ "bold", "italic", "bold_italic", "light", "medium", "semibold", "black" ]
        },
        body: {
          label: "Body Font",
          description: "Used for paragraphs and body text",
          required_variants: [ "family", "regular" ],
          common_variants: [ "bold", "italic", "bold_italic", "light", "medium", "semibold" ]
        },
        mono: {
          label: "Monospace Font",
          description: "Used for code blocks and preformatted text",
          required_variants: [ "family", "regular" ],
          common_variants: [ "bold", "italic", "bold_italic" ]
        },
        accent: {
          label: "Accent Font",
          description: "Optional font for special elements like collection titles, pullquotes, or emphasis",
          required_variants: [ "family", "regular" ],
          common_variants: [ "bold", "italic", "bold_italic", "light", "medium" ]
        }
      },
      # Common variants offered when adding a custom family
      custom_family_variants: [ "bold", "italic", "bold_italic", "light", "medium", "semibold", "black" ]
    }
  }.freeze

  PAYMENTS_CONFIG_SCHEMA = {
    test_keys: {
      label: "Stripe Test Keys",
      fields: {
        "publishable_key" => { type: :text,     label: "Publishable Key (Test)", hint: "Starts with pk_test_" },
        "secret_key"      => { type: :password, label: "Secret Key (Test)",      hint: "Starts with sk_test_" },
        "webhook_signing_secret" => { type: :password, label: "Webhook Signing Secret (Test)", hint: "Starts with whsec_" }
      }
    },
    live_keys: {
      label: "Stripe Live Keys",
      fields: {
        "publishable_key" => { type: :text,     label: "Publishable Key (Live)", hint: "Starts with pk_live_" },
        "secret_key"      => { type: :password, label: "Secret Key (Live)",      hint: "Starts with sk_live_" },
        "webhook_signing_secret" => { type: :password, label: "Webhook Signing Secret (Live)", hint: "Starts with whsec_" }
      }
    }
  }.freeze

  NEWSLETTERS_CONFIG_SCHEMA = {
    test_keys: {
      label: "Postmark Test Token",
      fields: {
        "server_token" => { type: :password, label: "Server Token (Test)", hint: "Your Postmark server API token for testing" }
      }
    },
    live_keys: {
      label: "Postmark Live Token",
      fields: {
        "server_token" => { type: :password, label: "Server Token (Live)", hint: "Your Postmark production server API token" }
      }
    }
  }.freeze

  SNIPCART_CONFIG_SCHEMA = {
    test_keys: {
      label: "Snipcart Test API Key",
      fields: {
        "api_key" => { type: :text, label: "Public API Key (Test)", hint: "Your Snipcart test public API key" }
      }
    },
    live_keys: {
      label: "Snipcart Live API Key",
      fields: {
        "api_key" => { type: :text, label: "Public API Key (Live)", hint: "Your Snipcart live public API key" }
      }
    }
  }.freeze

  helper_method :itunes_categories, :itunes_subcategories

  # Top-level iTunes podcast categories. Single source of truth —
  # used both by the inline category list in build_field_options_for_podcast
  # and by the new-podcast-setup modal so they stay in sync.
  def itunes_categories
    [
      "Arts", "Business", "Comedy", "Education", "Fiction", "Government",
      "Health & Fitness", "History", "Kids & Family", "Leisure", "Music",
      "News", "Religion & Spirituality", "Science", "Society & Culture",
      "Sports", "Technology", "True Crime", "TV & Film"
    ]
  end

  def itunes_subcategories
    {
      "Arts" => [ "Books", "Design", "Fashion & Beauty", "Food", "Performing Arts", "Visual Arts" ],
      "Business" => [ "Careers", "Entrepreneurship", "Investing", "Management", "Marketing", "Non-Profit" ],
      "Comedy" => [ "Comedy Interviews", "Improv", "Stand-Up" ],
      "Education" => [ "Courses", "How To", "Language Learning", "Self-Improvement" ],
      "Fiction" => [ "Comedy Fiction", "Drama", "Science Fiction" ],
      "Government" => [],  # ← No subcategories
      "Health & Fitness" => [ "Alternative Health", "Fitness", "Medicine", "Mental Health", "Nutrition", "Sexuality" ],
      "History" => [],  # ← No subcategories
      "Kids & Family" => [ "Education for Kids", "Parenting", "Pets & Animals", "Stories for Kids" ],
      "Leisure" => [ "Animation & Manga", "Automotive", "Aviation", "Crafts", "Games", "Hobbies", "Home & Garden", "Video Games" ],
      "Music" => [ "Music Commentary", "Music History", "Music Interviews" ],
      "News" => [ "Business News", "Daily News", "Entertainment News", "News Commentary", "Politics", "Sports News", "Tech News" ],
      "Religion & Spirituality" => [ "Buddhism", "Christianity", "Hinduism", "Islam", "Judaism", "Religion", "Spirituality" ],
      "Science" => [ "Astronomy", "Chemistry", "Earth Sciences", "Life Sciences", "Mathematics", "Natural Sciences", "Nature", "Physics", "Social Sciences" ],
      "Society & Culture" => [ "Documentary", "Personal Journals", "Philosophy", "Places & Travel", "Relationships" ],
      "Sports" => [ "Baseball", "Basketball", "Cricket", "Fantasy Sports", "Football", "Golf", "Hockey", "Rugby", "Running", "Soccer", "Swimming", "Tennis", "Volleyball", "Wilderness", "Wrestling" ],
      "Technology" => [],  # ← No subcategories
      "True Crime" => [],  # ← No subcategories
      "TV & Film" => [ "After Shows", "Film History", "Film Interviews", "Film Reviews", "TV Reviews" ]  # ← Was missing
    }
  end

  def index
    # Site-level configs
    global_files = [
      {
        name: "site.yml",
        path: "global/site.yml",
        type: "site",
        description: "Site title, URL, author info, and branding",
        edit_path: admin_edit_site_config_path
      },
      {
        name: "fonts.yml",
        path: "global/fonts.yml",
        type: "fonts",
        description: "Custom font configuration",
        edit_path: admin_edit_fonts_config_path
      }
    ]

    # Always show deploy.yml (ships with Roe)
    if File.exist?(SiteConfig::DEPLOY_FILE)
      global_files << {
        name: "deploy.yml",
        path: "global/deploy.yml",
        type: "deploy",
        description: "Deployment target (Kamal/Fly), server address, registry, and volume paths",
        edit_path: admin_edit_deploy_config_path
      }
    end

    # Add development.yml if it exists
    if File.exist?(SiteConfig::DEVELOPMENT_FILE)
      global_files << {
        name: "development.yml",
        path: "global/development.yml",
        type: "development",
        description: "Development features and debugging (ngrok hosts, etc.)",
        edit_path: admin_edit_development_config_path
      }
    end

    # Feature configs
    features_files = []

    if File.exist?(SiteConfig::FEATURES_PATH.join("members.yml"))
      features_files << {
        name: "members.yml",
        path: "features/members.yml",
        type: "features/members",
        edit_path: admin_edit_members_config_path
      }
    end

    if File.exist?(SiteConfig::FEATURES_PATH.join("podcast.yml"))
      features_files << {
        name: "podcast.yml",
        path: "features/podcast.yml",
        type: "features/podcast",
        edit_path: admin_edit_podcast_config_path
      }
    end

    if File.exist?(SiteConfig::FEATURES_PATH.join("store.yml"))
      features_files << {
        name: "store.yml",
        path: "features/store.yml",
        type: "features/store",
        edit_path: admin_edit_store_config_path
      }
    end

    # Default configs
    defaults_files = [
      {
        name: "cards.yml",
        path: "defaults/cards.yml",
        type: "defaults/cards",
        edit_path: admin_edit_cards_config_path
      },
      {
        name: "collections.yml",
        path: "defaults/collections.yml",
        type: "defaults/collections",
        edit_path: admin_edit_collections_config_path
      }
    ]

    # Build the config_files structure for the view
    @config_files = [
      {
        section: "Global",
        files: global_files
      },
      {
        section: "Features",
        files: features_files
      }
    ]

    # Integrations section — only shown when at least one integration feature is enabled
    integration_files = []

    if SiteFeature.payments_feature_enabled?
      integration_files << {
        name: "stripe.yml",
        path: "integrations/stripe.yml",
        description: "Stripe test keys",
        edit_path: admin_edit_payments_config_path,
        unconfigured: SiteFeature.payments_unconfigured?
      }
    end

    if SiteFeature.newsletters_feature_enabled?
      integration_files << {
        name: "postmark.yml",
        path: "integrations/postmark.yml",
        description: "Postmark test token",
        edit_path: admin_edit_newsletters_config_path,
        unconfigured: SiteFeature.newsletters_unconfigured?
      }
    end

    if SiteFeature.store_enabled?
      integration_files << {
        name: "snipcart.yml",
        path: "integrations/snipcart.yml",
        description: "Snipcart (store) API keys",
        edit_path: admin_edit_snipcart_integration_config_path,
        unconfigured: SiteFeature.snipcart_unconfigured?
      }
    end

    @config_files << {
      section: "Integrations",
      files: integration_files
    } if integration_files.any?

    @config_files << {
      section: "Defaults",
      files: defaults_files
    }
  end

  def edit_site
    @config_type = "site"
    @config_content = File.read(SiteConfig::SITE_FILE)
    @config_hash = YAML.load(@config_content) || {}
    @config_schema = SITE_CONFIG_SCHEMA
    render :edit
  end

  def update_site
    update_config("site", SiteConfig::SITE_FILE)
  end

  def edit_fonts
    @config_type = "fonts"
    @config_content = File.read(SiteConfig::FONTS_FILE)
    @config_hash = YAML.load(@config_content) || {}
    @config_schema = FONTS_CONFIG_SCHEMA
    @available_themes = list_available_themes
    render :edit
  end

  # Theme names available to scope fonts to. Master themes in app/themes/
  # plus any user themes in /site/theme/ (deduped by name).
  def list_available_themes
    names = Dir.glob(Rails.root.join("app/themes/*.css")).map { |f| File.basename(f, ".css") }
    user_dir = File.join(RoeSitePaths::SITE_PATH, "theme")
    names += Dir.glob(File.join(user_dir, "*.css")).map { |f| File.basename(f, ".css") } if Dir.exist?(user_dir)
    names.uniq.sort
  end

  def update_fonts
    update_config("fonts", SiteConfig::FONTS_FILE)
  end

  def edit_podcast
    podcast_config_path = SiteConfig::FEATURES_PATH.join("podcast.yml")

    unless File.exist?(podcast_config_path)
      SiteConfig.find_by("file_path LIKE ?", "%podcast.yml")&.destroy
      flash[:alert] = "Podcast configuration doesn't exist. Click 'Add Podcast Config' to create one."
      redirect_to admin_configs_path and return
    end

    @config_type = "podcast"
    @config_content = File.read(podcast_config_path)
    @config_hash = YAML.load(@config_content) || {}

    # Auto-surface the `audience` field on every podcast block when paid
    # memberships are configured, so admins always see/manage it (matches
    # how posts and pages auto-surface their site-gated fields). Empty
    # values save as `audience: ""` and the publish modal prompts before
    # anything goes live.
    if helpers.memberships_enabled?
      @config_hash.each do |key, podcast|
        next unless podcast.is_a?(Hash)
        podcast["audience"] ||= "" unless podcast.key?("audience")
      end
    end

    @field_options = build_field_options_for_podcast
    @field_help = build_field_help_for_podcast
    # Source of truth for which podcast fields are required (used by the
    # admin form to render the red asterisk next to the label).
    @field_required = PodcastConfig::REQUIRED_FIELDS
    render :edit
  end

  # Seed a podcast.yml entry from an RSS feed URL. The URL is fetched
  # synchronously here so any paywall token in it stays in request scope —
  # never persisted, never logged. Existing entries with the same key are
  # overwritten (this action is explicitly user-initiated; if the user
  # didn't want overwrite they wouldn't click the button).
  def seed_podcast_from_rss
    rss_url = params[:rss_url].to_s.strip

    if rss_url.blank?
      redirect_to admin_edit_podcast_config_path, alert: "Please paste a podcast RSS feed URL." and return
    end

    fetch = PodcastFeedFetcher.fetch(rss_url)
    unless fetch.success?
      redirect_to admin_edit_podcast_config_path, alert: "Could not load RSS feed: #{fetch.error}" and return
    end

    channel = fetch.data[:channel] || {}
    title = channel[:title].to_s
    if title.blank?
      redirect_to admin_edit_podcast_config_path, alert: "Feed had no <title> — cannot derive a podcast key." and return
    end

    key = PodcastConfigSeeder.derive_key(title)
    seeder = PodcastConfigSeeder.new(key, channel.transform_keys(&:to_s), mode: :overwrite)
    result = seeder.seed!

    redirect_to admin_edit_podcast_config_path,
                notice: "Podcast '#{title}' seeded as '#{key}' (#{result})."
  end

  def update_podcast
    update_config("features/podcast", SiteConfig::FEATURES_PATH.join("podcast.yml"))
  end

  def edit_cards
    @config_type = "cards"
    @config_content = File.read(SiteConfig::DEFAULTS_PATH.join("cards.yml"))
    @config_hash = YAML.load(@config_content) || {}
    @field_options = build_field_options_for_cards
    render :edit
  end

  def update_cards
    update_config("defaults/cards", SiteConfig::DEFAULTS_PATH.join("cards.yml"))
  end

  def edit_collections
    @config_type = "collections"
    @config_content = File.read(SiteConfig::DEFAULTS_PATH.join("collections.yml"))
    @config_hash = YAML.load(@config_content) || {}
    @field_options = build_field_options_for_collections
    render :edit
  end

  def update_collections
    update_config("defaults/collections", SiteConfig::DEFAULTS_PATH.join("collections.yml"))
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

  # GET — renders the "Enable Podcasts" setup form (full-page modal,
  # mirroring new_members_setup). The form carries the full canonical
  # field set + an RSS/Atom URL the user can optionally seed from.
  # Cancelling navigates away without writing anything; submitting
  # writes podcast.yml AND enables the feature in one shot.
  def new_podcast_setup
    if File.exist?(SiteConfig::FEATURES_PATH.join("podcast.yml"))
      flash[:alert] = "Podcast configuration already exists"
      redirect_to admin_configs_path and return
    end

    @podcast_data = PodcastConfig.default_entry
    @rss_url      = ""
    @image_url    = ""
    render :new_podcast_modal
  end

  # POST — server-side "Fill from feed" preview. Fetches + parses the
  # RSS/Atom URL, then re-renders the setup form with the canonical
  # fields populated. Failures (bad URL, no <title>, network) re-render
  # the form with an inline error and the user's current input
  # preserved, matching the agreed-upon UX.
  def preview_podcast_from_rss
    @rss_url      = params[:rss_url].to_s.strip
    @podcast_data = PodcastConfig.default_entry.merge(submitted_podcast_data)
    @image_url    = ""

    if @rss_url.blank?
      flash.now[:alert] = "Paste a podcast RSS or Atom feed URL to fill from."
      return render(:new_podcast_modal, status: :unprocessable_entity)
    end

    fetch = PodcastFeedFetcher.fetch(@rss_url)
    unless fetch.success?
      flash.now[:alert] = "Could not load feed: #{fetch.error}"
      return render(:new_podcast_modal, status: :unprocessable_entity)
    end

    channel = fetch.data[:channel] || {}
    if channel[:title].to_s.strip.empty?
      flash.now[:alert] = "Feed has no <title> — cannot derive a podcast."
      return render(:new_podcast_modal, status: :unprocessable_entity)
    end

    # Overwrite all canonical fields with what the feed gave us
    # (user explicitly asked for "Fill from feed"). The artwork
    # filename stays blank in the form — the actual download happens
    # at create_podcast time, using @image_url passed through as a
    # hidden field. PodcastConfigSeeder.entry_from_channel handles
    # the channel-key-to-canonical-field mapping (RSS vs Atom is
    # already collapsed by PodcastFeedParser into a uniform shape).
    @podcast_data = PodcastConfigSeeder.entry_from_channel(channel)
    @image_url    = channel[:image_url].to_s

    flash.now[:notice] = "Filled fields from feed. Review and adjust before enabling."
    render :new_podcast_modal, status: :unprocessable_entity
  end

  # POST — final submit. Writes podcast.yml as a single entry; if the
  # form carries a hidden image_url (from Fill-from-feed), downloads
  # the artwork too and uses the resulting filename for the artwork
  # field. Form values take precedence over feed-derived values
  # everywhere except artwork (user only sees the filename, not a
  # URL).
  def create_podcast
    if File.exist?(SiteConfig::FEATURES_PATH.join("podcast.yml"))
      flash[:alert] = "Podcast configuration already exists"
      redirect_to admin_configs_path and return
    end

    data = PodcastConfig.default_entry.merge(submitted_podcast_data)
    title = data["title"].to_s.strip

    if title.blank?
      @podcast_data = data
      @rss_url      = params[:rss_url].to_s
      @image_url    = params[:image_url].to_s
      flash.now[:alert] = "Title is required to create a podcast."
      return render(:new_podcast_modal, status: :unprocessable_entity)
    end

    key = PodcastConfigSeeder.derive_key(title)

    image_url = params[:image_url].to_s
    if image_url.present?
      data["artwork"] = PodcastConfigSeeder.fetch_artwork(key, image_url)
    end

    write_single_podcast_entry(key, data)
    SiteConfig.sync_from_file("features/podcast")
    flash[:notice] = "Podcast '#{title}' created and feature enabled."
    redirect_to admin_edit_podcast_config_path
  end

  def delete_podcast
    file_path = SiteConfig::FEATURES_PATH.join("podcast.yml")

    File.delete(file_path) if File.exist?(file_path)
    SiteConfig.find_by("file_path LIKE ?", "%podcast.yml")&.destroy
    SiteConfig.reload!("features/podcast")

    flash[:notice] = "Podcast configuration deleted successfully"
    redirect_to admin_configs_path
  end

  def edit_members
    members_config_path = SiteConfig::FEATURES_PATH.join("members.yml")

    unless File.exist?(members_config_path)
      flash[:alert] = "Members configuration doesn't exist."
      redirect_to admin_configs_path and return
    end

    @config_type = "members"
    @config_content = File.read(members_config_path)
    @config_hash = YAML.load(@config_content) || {}
    @field_options = build_field_options_for_members
    @field_hints = build_field_hints_for_members  # ← Add this

    render :edit
  end

  def update_members
    update_config("features/members", SiteConfig::FEATURES_PATH.join("members.yml"))
  end

  def new_members_setup
    if File.exist?(SiteConfig::FEATURES_PATH.join("members.yml"))
      flash[:alert] = "Members configuration already exists"
      redirect_to admin_configs_path
    else
      render :new_members_modal
    end
  end

  def create_members
    show_paid = params[:show_paid_content] == "true"
    payments_enabled = params[:payments_enabled] == "true"
    payment_price = params[:payment_price].presence || "0.00"
    newsletter_enabled = params[:newsletter_enabled] == "true"

    ConfigGenerator.new.generate_members_defaults(
      show_paid_content: show_paid,
      payments_enabled: payments_enabled,
      payment_price: payment_price,
      newsletter_enabled: newsletter_enabled
    )
    SiteConfig.sync_from_file("defaults/members")

    # Sync the new upgrade page
    ContentSync.new.sync_pages

    flash[:notice] = "Members feature enabled successfully"
    redirect_to admin_configs_path
  end

  def delete_members
    file_path = SiteConfig::FEATURES_PATH.join("members.yml")

    File.delete(file_path) if File.exist?(file_path)
    SiteConfig.find_by("file_path LIKE ?", "%members.yml")&.destroy
    SiteConfig.reload!("features/members")

    flash[:notice] = "Members feature disabled successfully"
    redirect_to admin_configs_path
  end

  def new_store_setup
    if File.exist?(SiteConfig::FEATURES_PATH.join("store.yml"))
      flash[:alert] = "Store configuration already exists"
      redirect_to admin_configs_path
    else
      render :new_store_modal
    end
  end

  def create_store
    currency = params[:currency].presence || "usd"
    default_domain = params[:default_domain].presence || ""

    # Create store.yml with configuration (no API keys)
    ConfigGenerator.generate_store_defaults(
      currency: params[:currency],
      default_domain: params[:default_domain],
      product_categories: params[:product_categories]
    )
    SiteConfig.sync_from_file("features/store")

    flash[:notice] = "Store feature enabled! Now configure your Snipcart API keys."
    redirect_to admin_edit_snipcart_integration_config_path
  end

  def edit_store
    store_config_path = SiteConfig::FEATURES_PATH.join("store.yml")

    unless File.exist?(store_config_path)
      SiteConfig.find_by("file_path LIKE ?", "%store.yml")&.destroy
      flash[:alert] = "Store configuration doesn't exist. Click 'Enable Store' to create one."
      redirect_to admin_configs_path and return
    end

    @config_type = "store"
    @config_content = File.read(store_config_path)
    @config_hash = YAML.load(@config_content) || {}
    render :edit
  end

  def update_store
    update_config("features/store", SiteConfig::FEATURES_PATH.join("store.yml"))
  end

  def delete_store
    file_path = SiteConfig::FEATURES_PATH.join("store.yml")

    File.delete(file_path) if File.exist?(file_path)
    SiteConfig.find_by("file_path LIKE ?", "%store.yml")&.destroy
    SiteConfig.reload!("features/store")

    flash[:notice] = "Store feature disabled successfully"
    redirect_to admin_configs_path
  end

  def clear_deploy_password
    DeploySecrets.delete_all
    flash[:notice] = "Registry password cleared."
    redirect_to admin_edit_deploy_config_path
  end

  def edit_deploy
    @config_hash         = File.exist?(SiteConfig::DEPLOY_FILE) ? (YAML.load_file(SiteConfig::DEPLOY_FILE) || {}) : {}
    @deploy_secrets      = DeploySecrets.current
    @master_key_present  = DeployConfigGenerator.master_key_present?
    @fly_cli_available   = DeployConfigGenerator.fly_cli_available?
    @kamal_cli_available = DeployConfigGenerator.kamal_cli_available?
    @site_size_bytes     = site_size_bytes
    render :edit_deploy
  end

  def update_deploy
    dp = params[:deploy_config] || {}

    config = {
      "target"   => dp[:target].to_s.presence || "kamal",
      "app_name" => dp[:app_name].to_s.strip,
      "ssl"      => dp[:ssl] == "1",
      "kamal"    => {
        "servers"           => (dp.dig(:kamal, :servers) || []).reject(&:blank?),
        "registry_username" => dp.dig(:kamal, :registry_username).to_s.strip,
        "image_name"        => dp.dig(:kamal, :image_name).to_s.strip,
        "host"              => dp.dig(:kamal, :host).to_s.strip
      },
      "fly"      => {
        "region"         => dp.dig(:fly, :region).to_s.strip,
        "vm_memory"      => dp.dig(:fly, :vm_memory).to_s.strip,
        "volume_size_gb" => dp.dig(:fly, :volume_size_gb).to_i
      }
    }

    FileUtils.mkdir_p(File.dirname(SiteConfig::DEPLOY_FILE))
    write_yaml(SiteConfig::DEPLOY_FILE, config)
    SiteConfig.sync_from_file("deploy")

    # Save registry password if a new one was provided (blank = keep existing).
    deploy_secrets   = DeploySecrets.current
    new_password     = params.dig(:deploy_secrets, :registry_password).presence
    if new_password
      deploy_secrets.registry_password = new_password
      deploy_secrets.save!
    end

    # Generate platform config files, then .kamal/secrets when ready.
    generated = []
    alerts    = []

    begin
      generated += DeployConfigGenerator.generate!.map { |r| r[:file] }
    rescue DeployConfigGenerator::GenerationError => e
      Rails.logger.error "DeployConfigGenerator.generate! failed: #{e.message}"
      alerts << e.message
    end

    if config["target"] == "kamal" &&
       deploy_secrets.registry_password.present? &&
       DeployConfigGenerator.master_key_present?
      begin
        DeployConfigGenerator.generate_secrets!
        generated << ".kamal/secrets"
      rescue DeployConfigGenerator::GenerationError => e
        Rails.logger.error "DeployConfigGenerator.generate_secrets! failed: #{e.message}"
        alerts << e.message
      end
    end

    flash[:notice] = "Deploy configuration saved#{generated.any? ? ". Generated: #{generated.join(', ')}" : ""}."
    flash[:alert]  = alerts.join(" ") if alerts.any?

    redirect_to admin_edit_deploy_config_path
  rescue => e
    Rails.logger.error "Failed to update deploy config: #{e.message}"
    flash.now[:error] = "Failed to update deploy configuration: #{e.message}"
    @config_hash         = config || {}
    @deploy_secrets      = DeploySecrets.current
    @master_key_present  = DeployConfigGenerator.master_key_present?
    @fly_cli_available   = DeployConfigGenerator.fly_cli_available?
    @kamal_cli_available = DeployConfigGenerator.kamal_cli_available?
    @site_size_bytes     = site_size_bytes
    render :edit_deploy, status: :unprocessable_entity
  end

  def edit_development
    development_config_path = SiteConfig::DEVELOPMENT_FILE

    unless File.exist?(development_config_path)
      flash[:alert] = "Development configuration doesn't exist."
      redirect_to admin_configs_path and return
    end

    @config_type = "development"
    @config_content = File.read(development_config_path)
    @config_hash = YAML.load(@config_content) || {}
    @allowed_hosts = @config_hash["allowed_hosts"] || []
    render :edit_development
  end

  def update_development
    # Get hosts from params, filter out empty ones
    hosts = params[:allowed_hosts]&.reject(&:blank?) || []

    # Build YAML content
    if hosts.any?
      yaml_content = "allowed_hosts:\n"
      hosts.each do |host|
        yaml_content += "  - #{host}\n"
      end
    else
      yaml_content = "allowed_hosts: []\n"
    end

    # Write to file
    File.write(SiteConfig::DEVELOPMENT_FILE, yaml_content)

    # Sync to database
    SiteConfig.sync_from_file("development")

    flash[:notice] = "Development configuration updated successfully"
    redirect_to admin_configs_path
  rescue => e
    flash.now[:error] = "Failed to update configuration: #{e.message}"
    @config_type = "development"
    @config_content = File.read(SiteConfig::DEVELOPMENT_FILE)
    @config_hash = YAML.load(@config_content) || {}
    @allowed_hosts = @config_hash["allowed_hosts"] || []
    render :edit_development
  end

  def enable_development
    unless Rails.env.development?
      flash[:alert] = "Development features can only be enabled in development mode"
      redirect_to admin_configs_path and return
    end

    if File.exist?(SiteConfig::DEVELOPMENT_FILE)
      flash[:alert] = "Development configuration already exists"
    else
      # Create development.yml with default content
      FileUtils.mkdir_p(SiteConfig::DEVELOPMENT_FILE.dirname)
      File.write(SiteConfig::DEVELOPMENT_FILE, <<~YAML)
        allowed_hosts:
          - your-site.ngrok-free.app
      YAML

      SiteConfig.sync_from_file("development")
      flash[:notice] = "Development features enabled! Edit development.yml to add allowed hosts."
    end

    redirect_to admin_configs_path
  end

  def delete_development
    file_path = SiteConfig::DEVELOPMENT_FILE

    File.delete(file_path) if File.exist?(file_path)
    SiteConfig.find_by("file_path LIKE ?", "%development.yml")&.destroy
    SiteConfig.reload!("development")

    flash[:notice] = "Development configuration deleted successfully"
    redirect_to admin_configs_path
  end

  def edit_payments
    path = File.join(SiteConfig::INTEGRATIONS_PATH, "stripe.yml")
    unless File.exist?(path)
      ConfigGenerator.new.generate_payments_config
    end
    @config_type    = "payments"
    @config_content = File.read(path)
    @config_hash    = (YAML.load(@config_content) || {})["test"] || {}
    @stripe_config  = StripeConfig.current
    # Auto-verify if the file holds keys but the model hasn't checked them
    # yet. Lets an admin drop stripe.yml in place and have the connection
    # status reflect reality on first page load, without having to click
    # "Save Test Keys" purely to trigger verification.
    @stripe_config.verify! if @stripe_config.keys_present? && @stripe_config.verified_at.nil?
    @schema         = PAYMENTS_CONFIG_SCHEMA
    render :edit_integration
  end

  def update_payments
    path = File.join(SiteConfig::INTEGRATIONS_PATH, "stripe.yml")
    test_data = params[:test] || {}

    existing = File.exist?(path) ? (YAML.load_file(path) || {}) : {}
    existing["test"] ||= {}
    # Skip masked placeholder values — user didn't change those fields
    test_data.each { |k, v| existing["test"][k] = v if v.present? && v != "•" * 16 }

    write_yaml(path, existing)
    SiteConfig.sync_from_file("integrations/stripe")

    # Save to StripeConfig and verify
    stripe = StripeConfig.current
    StripeConfig.save_test_config(existing["test"])
    stripe.verify!

    flash[:notice] = "Stripe configuration saved"
    redirect_to admin_edit_payments_config_path
  end

  def verify_payments
    stripe = StripeConfig.current
    success = stripe.verify!
    render json: {
      verified:    success,
      verified_at: success ? stripe.verified_at.iso8601 : nil,
      error:       success ? nil : "Could not connect to Stripe. Check your test keys."
    }
  end

  def update_payments_live
    unless Rails.env.production?
      flash[:notice] = "Live keys are only saved in production."
      redirect_to admin_edit_payments_config_path and return
    end

    stripe = StripeConfig.current
    apply_live_keys(stripe, params[:live] || {}, %w[publishable_key secret_key webhook_signing_secret])

    if stripe.save
      stripe.verify!
      flash[:notice] = "Stripe live keys saved"
    else
      flash[:error] = "Failed to save Stripe live keys"
    end
    redirect_to admin_edit_payments_config_path
  end

  def update_payments_mode
    update_integration_mode(StripeConfig.current, "Payments")
    redirect_to admin_edit_payments_config_path
  end

  def disconnect_payments
    StripeConfig.current.disconnect!
    flash[:notice] = "Stripe disconnected. All keys cleared."
    redirect_to admin_edit_payments_config_path
  end

  def edit_newsletters
    path = File.join(SiteConfig::INTEGRATIONS_PATH, "postmark.yml")
    unless File.exist?(path)
      ConfigGenerator.new.generate_newsletters_config
    end
    @config_type      = "newsletters"
    @config_content   = File.read(path)
    @config_hash      = (YAML.load(@config_content) || {})["test"] || {}
    @postmark_config  = PostmarkConfig.current
    @postmark_config.verify! if @postmark_config.keys_present? && @postmark_config.verified_at.nil?
    @schema           = NEWSLETTERS_CONFIG_SCHEMA
    render :edit_integration
  end

  def update_newsletters
    path = File.join(SiteConfig::INTEGRATIONS_PATH, "postmark.yml")
    test_data = params[:test] || {}

    existing = File.exist?(path) ? (YAML.load_file(path) || {}) : {}
    existing["test"] ||= {}
    test_data.each { |k, v| existing["test"][k] = v if v.present? && v != "•" * 16 }

    write_yaml(path, existing)
    SiteConfig.sync_from_file("integrations/postmark")

    PostmarkConfig.save_test_config(existing["test"])
    PostmarkConfig.current.verify!

    flash[:notice] = "Postmark configuration saved"
    redirect_to admin_edit_newsletters_config_path
  end

  def verify_newsletters
    postmark = PostmarkConfig.current
    success  = postmark.verify!
    render json: {
      verified:    success,
      verified_at: success ? postmark.verified_at.iso8601 : nil,
      error:       success ? nil : "Could not connect to Postmark. Check your server token."
    }
  end

  def update_newsletters_live
    unless Rails.env.production?
      flash[:notice] = "Live keys are only saved in production."
      redirect_to admin_edit_newsletters_config_path and return
    end

    postmark = PostmarkConfig.current
    apply_live_keys(postmark, params[:live] || {}, %w[server_token])

    if postmark.save
      postmark.verify!
      flash[:notice] = "Postmark live token saved"
    else
      flash[:error] = "Failed to save Postmark live token"
    end
    redirect_to admin_edit_newsletters_config_path
  end

  def update_newsletters_mode
    update_integration_mode(PostmarkConfig.current, "Newsletters")
    redirect_to admin_edit_newsletters_config_path
  end

  def disconnect_newsletters
    PostmarkConfig.current.disconnect!
    flash[:notice] = "Postmark disconnected. All tokens cleared."
    redirect_to admin_edit_newsletters_config_path
  end

  def regenerate_postmark_webhook_token
    PostmarkConfig.current.regenerate_webhook_token!
    flash[:notice] = "Webhook token regenerated. Update the URL in Postmark!"
    redirect_to admin_edit_newsletters_config_path
  end

  def edit_snipcart
    path = File.join(SiteConfig::INTEGRATIONS_PATH, "snipcart.yml")
    unless File.exist?(path)
      ConfigGenerator.new.generate_snipcart_config
    end
    @config_type      = "snipcart"
    @config_content   = File.read(path)
    @config_hash      = (YAML.load(@config_content) || {})["test"] || {}
    @snipcart_config  = SnipcartConfig.current
    @snipcart_config.verify! if @snipcart_config.keys_present? && @snipcart_config.verified_at.nil?
    @schema           = SNIPCART_CONFIG_SCHEMA
    render :edit_integration
  end

  def update_snipcart
    path = File.join(SiteConfig::INTEGRATIONS_PATH, "snipcart.yml")
    test_data = params[:test] || {}

    existing = File.exist?(path) ? (YAML.load_file(path) || {}) : {}
    existing["test"] ||= {}
    test_data.each { |k, v| existing["test"][k] = v if v.present? && v != "•" * 16 }

    write_yaml(path, existing)
    SiteConfig.sync_from_file("integrations/snipcart")

    SnipcartConfig.save_test_config(existing["test"])
    SnipcartConfig.current.verify!

    flash[:notice] = "Store (Snipcart) configuration saved"
    redirect_to admin_edit_snipcart_integration_config_path
  end

  def update_snipcart_live
    unless Rails.env.production?
      flash[:notice] = "Live keys are only saved in production."
      redirect_to admin_edit_snipcart_integration_config_path and return
    end

    snipcart = SnipcartConfig.current
    apply_live_keys(snipcart, params[:live] || {}, %w[api_key])

    if snipcart.save
      snipcart.verify!
      flash[:notice] = "Snipcart live key saved"
    else
      flash[:error] = "Failed to save Snipcart live key"
    end
    redirect_to admin_edit_snipcart_integration_config_path
  end

  def update_snipcart_mode
    update_integration_mode(SnipcartConfig.current, "Store")
    redirect_to admin_edit_snipcart_integration_config_path
  end

  def disconnect_snipcart
    SnipcartConfig.current.disconnect!
    flash[:notice] = "Snipcart disconnected. All keys cleared."
    redirect_to admin_edit_snipcart_integration_config_path
  end

  def verify_snipcart
    snipcart = SnipcartConfig.current
    success  = snipcart.verify!
    render json: {
      verified:    success,
      verified_at: success ? snipcart.verified_at.iso8601 : nil,
      error:       success ? nil : "Could not connect to Snipcart. Check your API key."
    }
  end

  private

  # Write a Ruby hash to YAML at `path` without the leading `---`
  # document separator. Hand-authored Roe config files don't use it,
  # so generated ones shouldn't either — purely stylistic, but keeps
  # diffs clean across the codebase.
  def write_yaml(path, data)
    File.write(path, data.to_yaml.sub(/\A---\s*\n/, ""))
  end

  # Extract just the canonical podcast fields from form params,
  # stringified. Anything outside CANONICAL_FIELDS is silently
  # dropped — we don't want stray params landing in podcast.yml.
  def submitted_podcast_data
    return {} unless params[:podcast].is_a?(ActionController::Parameters)
    params[:podcast]
      .permit(PodcastConfig::CANONICAL_FIELDS)
      .to_h
      .transform_values(&:to_s)
  end

  # Write podcast.yml as a single-entry file. Same format as
  # PodcastConfigSeeder produces (no document marker, since the
  # admin form-based YAML editor saves without one).
  def write_single_podcast_entry(key, data)
    path = SiteConfig::FEATURES_PATH.join("podcast.yml")
    FileUtils.mkdir_p(File.dirname(path))
    yaml = { key => data }.to_yaml.sub(/\A---\s*\n/, "")
    File.write(path, yaml)
  end

  # Sum of all file sizes the SiteSync ledger would track under /site.
  # Used by the deploy-config view to suggest a sensible Fly volume
  # size and to warn when the configured volume is getting tight.
  # Cached for 5 minutes so a hot reload loop doesn't re-stat thousands
  # of files — accuracy isn't critical here, this is a suggestion.
  def site_size_bytes
    Rails.cache.fetch("admin:deploy:site_size_bytes", expires_in: 5.minutes) do
      SiteSync::Ledger.current.values.sum { |entry| entry["size"].to_i }
    end
  rescue => e
    Rails.logger.warn "[Admin::ConfigsController] site_size_bytes failed: #{e.message}"
    0
  end

  # Apply live-key params to an integration record. Param names are
  # the bare field (e.g. "publishable_key"); the model attribute gets
  # "_live" appended. Skip masked placeholders so the user can save
  # the form without re-entering already-stored secrets.
  def apply_live_keys(record, params_hash, fields)
    fields.each do |field|
      value = params_hash[field]
      next if value.blank? || value == "•" * 16
      record.public_send("#{field}_live=", value)
    end
  end

  # Update the active mode (test/live) on an integration record and
  # set a flash. Caller handles the redirect.
  def update_integration_mode(record, label)
    new_mode = params[:mode].to_s
    unless %w[test live].include?(new_mode)
      flash[:error] = "Invalid mode: #{new_mode.inspect}"
      return
    end

    if new_mode == "live" && record.respond_to?(:live_mode_ready?) && !record.live_mode_ready?
      flash[:error] = "Add live keys before switching to Live mode"
      return
    end

    record.mode = new_mode
    if record.save
      flash[:notice] = "#{label} mode set to #{new_mode.capitalize}"
    else
      flash[:error] = "Failed to update #{label.downcase} mode"
    end
  end

  def sync_stripe_payments(members_config)
    payments_config = members_config&.dig("payments")

    # If payments not configured or not enabled, just return success
    unless payments_config && (payments_config["enabled"] == true || payments_config["enabled"] == "true")
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
      "type" => [ "episodic", "serial" ],
      "category" => [
        "", # Blank option
        "Arts", "Business", "Comedy", "Education", "Fiction", "Government",
        "Health & Fitness", "History", "Kids & Family", "Leisure", "Music",
        "News", "Religion & Spirituality", "Science", "Society & Culture",
        "Sports", "Technology", "True Crime", "TV & Film"
      ],
      "category_2" => [
        "",
        "Arts", "Business", "Comedy", "Education", "Fiction", "Government",
        "Health & Fitness", "History", "Kids & Family", "Leisure", "Music",
        "News", "Religion & Spirituality", "Science", "Society & Culture",
        "Sports", "Technology", "True Crime", "TV & Film"
      ],
      # Note: subcategory/subcategory_2 are arrays, handled by JS
      "language" => [ "en", "es", "fr", "de", "it", "pt", "ja", "zh", "ko", "ru" ],
      "explicit" => [ "false", "true" ],
      "episode_type" => [ "full", "trailer", "bonus" ],
      # Per-podcast audience gate. Renders as a select when the field is
      # present (auto-surfaced above when payments are enabled).
      "audience" => [ "everyone", "paid" ]
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
      "default_source" => [ "posts", "pages", "documentation" ],
      "default_post_type" => [ "all" ] + existing_post_types,
      "default_order" => [ "date", "date-asc", "title", "filename" ],
      "default_template" => [ "list", "compact", "links" ],
      "items_per_page" => [ "10", "20", "25", "50", "100" ]
    }
  end

  def build_field_options_for_cards
    {
      "post-link.default_style" => [ "small", "large" ],
      "pullquote.default_position" => [ "center", "left", "right" ]
    }
  end

  def build_field_options_for_members
    {
      "payments.enabled" => [ "false", "true" ],
      "payments.mode" => [ "memberships", "donations", "both" ],
      "newsletter.enabled" => [ "false", "true" ],
      "everyone.show_paid_content" => [ "true", "false" ]
    }
  end

  # Longer explanations that render as a hover tooltip next to a field's
  # label (via shared/_help_tooltip). Keyed by top-level field name.
  # Each entry is { text:, title?: } — text can be html_safe for simple
  # formatting (e.g. <strong>, <br>).
  def build_field_help_for_podcast
    {
      "type" => {
        title: "Episodic vs. Serial",
        text: ("<strong>Episodic</strong> — episodes stand alone and can be played in any order. Apple Podcasts shows newest first. Good for interviews, news, talk shows.<br><br>" \
               "<strong>Serial</strong> — episodes are meant to be played in order, like chapters. Apple shows oldest first. Good for narrative shows, audio dramas, limited series.").html_safe
      }
    }
  end

  def build_field_hints_for_members
    # Get currency from Stripe if connected
    stripe_config = StripeConfig.current
    currency = stripe_config.connected? ? stripe_config.default_currency.upcase : "USD"

    {
      "payments.enabled" => "Turn on the payments system (requires connection to your Stripe account). Then choose what you want to offer in the mode field below.",
      "payments.mode" => "memberships = lifetime paid access (price below). donations = one-time support payments (no membership granted). both = offer both flows.",
      "payments.price" => "Membership price in #{currency} (only used when mode is memberships or both, e.g., 49.00)",
      "payments.donation_amounts" => "Preset donation amounts in #{currency} (only used when mode is donations or both, e.g., [5, 10, 20, 50])",
      "newsletter.enabled" => "Enable newsletter & email sending via Postmark (requires Postmark account & configuration)",
      "everyone.show_paid_content" => "Show paid post links to public visitors and free members. They will see a lock icon next to paid content and be encouraged to upgrade to view it."
    }
  end

  def update_config(type, file_path)
    content = params[:content]

    # Load old config to compare (only for site config)
    old_config = nil
    if type == "site" && File.exist?(file_path)
      old_config = YAML.load_file(file_path) rescue {}
    end

    # Validate YAML syntax
    begin
      new_config = YAML.load(content)
    rescue Psych::SyntaxError => e
      flash.now[:error] = "Invalid YAML syntax: #{e.message}"
      @config_type = type.split("/").last
      @config_content = content
      render :edit and return
    end

    # Write to file
    File.write(file_path, content)

    # Sync to database and clear cache
    SiteConfig.sync_from_file(type)

    # Handle different config types
    case type
    when "site"
      Rails.cache.clear

      # Auto-generate when enabling static mode
      if old_config && !old_config["static_generation_enabled"] && new_config["static_generation_enabled"]
        StaticGenerator.new.generate_all
        flash[:notice] = "Site configuration updated and static site generated successfully"
      else
        flash[:notice] = "Site configuration updated successfully"
      end

    when "defaults/members"
      Rails.cache.clear

      # Sync Stripe product/price if payments are enabled
      sync_result = sync_stripe_payments(new_config)

      # Regenerate collections if static mode is enabled
      if SiteConfig.current("site")&.static_generation_enabled
        StaticGenerator.new.generate_all
        flash[:notice] = sync_result[:message] + " and static site regenerated"
      else
        flash[:notice] = sync_result[:message]
      end

    else
      flash[:notice] = "#{type.split('/').last.capitalize} configuration updated successfully"
    end

    # Dynamic redirect based on type
    config_key = type.split("/").last
    redirect_to send("admin_edit_#{config_key}_config_path")
  rescue => e
    flash.now[:error] = "Failed to update configuration: #{e.message}"
    @config_type = type.split("/").last
    @config_content = content
    render :edit
  end
end
