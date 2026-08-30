class Admin::ConfigsController < Admin::BaseController
  # A config save may add/remove a /media/ reference (e.g. the site logo),
  # so any non-GET config action busts the media-usage backlink cache.
  after_action :invalidate_media_usage_index

  # Structured editors that fall back to the raw YAML editor when their file
  # can't be parsed. Maps the edit action → the SiteConfig type (also the
  # file_path_for key). The matching path helper is always
  # admin_<action>_config_path, so we derive it rather than list it twice.
  RAW_EDITABLE_CONFIGS = {
    "edit_site"        => "site",
    "edit_content"     => "content",
    "edit_fonts"       => "fonts",
    "edit_podcast"     => "features/podcast",
    "edit_cards"       => "defaults/cards",
    "edit_collections" => "defaults/collections",
    "edit_members"     => "features/members",
    "edit_store"       => "features/store"
  }.freeze

  # When a structured editor above hits malformed YAML, don't 500 — send the
  # admin to the raw editor for that file so they can fix it by hand. Any other
  # source of a syntax error re-raises as before.
  rescue_from Psych::SyntaxError, with: :handle_unparseable_config

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
          hint: "Copy logo url from GLOBAL IMAGES."
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
          hint: "Copy logo url from GLOBAL IMAGES.",
          placeholder: "favicon.ico"
        },
        "social_image" => {
          type: :text,
          label: "Social Image",
          hint: "Default image shown when your site is shared on social platforms (Facebook, X, LinkedIn, iMessage, Slack). Recommended size: 1200×630.",
          placeholder: "social-share.jpg"
        },
        "social_image_override" => {
          type: :checkbox,
          label: "Always use Social Image",
          hint: "When checked, the Social Image above is used for all pages and posts when your site is shared on social media — even those with their own image. This does not affect your site, only how it appears in social media posts. Useful for consistent brand presence on social platforms.",
          depends_on: "social_image"
        },
        "social_image_alt" => {
          type: :text,
          label: "Social Image Alt Text",
          hint: "Describes the social image for screen readers + social card previews. Skip when posts/pages set their own image_alt.",
          placeholder: "Roe — open-source CMS"
        },
        "twitter_handle" => {
          type: :text,
          label: "Twitter / X handle",
          hint: "Used for the twitter:site meta tag (\"via @yourhandle\" in embedded cards). Leading @ optional.",
          placeholder: "@yourhandle"
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

    site_sync: {
      label: "Site Sync",
      fields: {
        "sync_transport" => {
          type: :select,
          label: "Transport",
          options: [ "http", "rsync" ],
          hint: "Protocol that Site Sync uses to sync files to/from a live site. HTTP (recommended) works over HTTPS with a shared token. rsync requires SSH to host."
        },
        "sync_confirm_deletions_over" => {
          type: :text,
          label: "Confirm deletions over",
          placeholder: "0",
          hint: "Site Sync deletes files. If a file is deleted on your Live site and you sync the site, it will be deleted locally and vice-versa. This is a threshold for when you will be warned about file deletions. 0 means you'll be warned everytime. '5' means you'll be warned if 6 or more files will be deleted. Set to 'never' to turn off warnings."
        }
      }
    },

    updates: {
      label: "Updates",
      fields: {
        "update_channel" => {
          type: :checkbox,
          on_value: "nightly",
          off_value: "stable",
          label: "Nightly updates",
          hint: "Receive pre-release (nightly) versions instead of stable releases. Off = stable."
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

  # security.yml — rate limits for the public endpoints. Field keys are dotted
  # so the editor buries them into nested YAML (limits.magic_link.to →
  # limits: { magic_link: { to: … } }), the same way theme.active does.
  #
  # Labels say what the limit protects rather than naming the endpoint, because
  # the person setting it is deciding how much room to give a reader.
  SECURITY_LIMIT_LABELS = {
    "magic_link" => [ "Sign-in emails", "per email address" ],
    "signup"     => [ "Sign-ups", "per connection" ],
    "checkout"   => [ "Sign-up with checkout", "per connection" ],
    "token"      => [ "Link and token attempts", "per connection" ]
  }.freeze

  SECURITY_CONFIG_SCHEMA = {
    rate_limiting: {
      label: "Rate Limiting",
      fields: {
        "enabled" => {
          type: :checkbox,
          label: "Limit repeated requests",
          hint: "Slows down abuse of the endpoints that send email, create accounts or accept tokens. " \
                "It is not protection against a denial-of-service attack — a flood is stopped at your host " \
                "or CDN, before it ever reaches Roe."
        }
      }
    },

    ai_crawlers: {
      label: "AI Crawlers",
      fields: {
        "ai_crawlers" => {
          type: :select,
          label: "AI crawlers",
          options: [
            [ "Block training and AI answers", "block_all" ],
            [ "Block training only", "block_training" ],
            [ "Allow everything", "allow" ]
          ],
          hint: "Written into robots.txt. Blocking training keeps your writing out of model training sets; " \
                "blocking AI answers as well takes the site out of AI search results, which is a real cost. " \
                "Ordinary search engines are never blocked either way. robots.txt is a request — the large " \
                "operators honour it, anything spoofing its user agent does not, so anything that must not be " \
                "read by a machine belongs behind an audience setting instead."
        }
      }
    },

    limits: {
      label: "Limits",
      fields: RateLimits::DEFAULTS.each_with_object({}) do |(name, default), fields|
        label, scope = SECURITY_LIMIT_LABELS.fetch(name, [ name.humanize, "per connection" ])
        fields["limits.#{name}.to"] = {
          type: :text,
          label: "#{label} allowed",
          hint: "How many, #{scope}. Default #{default['to']}."
        }
        fields["limits.#{name}.within"] = {
          type: :text,
          label: "#{label} — minutes",
          hint: "The window those are counted in. Default #{default['within']}."
        }
      end.freeze
    }
  }.freeze

  # Content settings — split into its own content.yml (search nested). Field
  # keys are dotted so the editor buries them into nested YAML
  # (search.all_pages → search: { all_pages: ... }), the same way theme.active
  # does.
  CONTENT_CONFIG_SCHEMA = {
    content: {
      label: "Global",
      fields: {
        "soft_line_breaks" => {
          type: :checkbox,
          label: "Respect single line breaks",
          hint: "By default Markdown needs two trailing spaces (or a blank line) to start a new line. Turn on to make every single line break in your content show as a line break."
        },
        "heading_links" => {
          type: :checkbox,
          label: "Heading links",
          hint: "Show a copy-link icon when hovering a heading on your public site (desktop only). Click it to copy a link straight to that section."
        }
      }
    },

    search: {
      label: "Search",
      fields: {
        "search.all_pages" => {
          type: :checkbox,
          label: "Include all pages in search",
          hint: "By default only pages linked in the navigation or footer are searchable. Turn on to index every published page."
        },
        "docs.roe" => {
          type: :select,
          label: "Roe's documentation",
          options: [ "local", "published", "searchable" ],
          # Matches Documentation.roe_docs_mode's fallback. Without it an unset
          # setting shows the empty "Select..." option, which reads as "off"
          # rather than as the default it actually is.
          default: "local",
          hint: "What happens to Roe's bundled documentation (documentation/roe) on your site.<br>" \
                "**local (default)** — kept on this computer, not sent to your live site.<br>" \
                "<strong>published</strong> — sent to your live site but left out of your search results.<br>" \
                "<strong>searchable</strong> — sent to your live site and in search."
        },
        "search.results_when_opened" => {
          type: :checkbox,
          label: "Show results before typing",
          hint: "By default, search doesn't show results until you type but if you want results to show up before typing, enable this option."
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
      label: "Postmark Test Server API Token",
      fields: {
        "server_token" => { type: :password, label: "Server Token (Test)", hint: "Your test Postmark server API token" }
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
      label: "Test & Local",
      fields: {
        "snippet" => { type: :textarea, label: "Snippet (Test)", hint: "Paste the full Snipcart snippet from your Test mode dashboard. Test mode uses fake payments and works locally." }
      }
    },
    live_keys: {
      label: "Live & Static Site",
      fields: {
        "snippet" => { type: :textarea, label: "Snippet (Live)", hint: "Paste the full Snipcart snippet from your Live mode dashboard. Set this once — the same snippet runs your local store and the static-site build." }
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
        name: "content.yml",
        path: "global/content.yml",
        type: "content",
        description: "Content rendering (line breaks, heading links) and search",
        edit_path: admin_edit_content_config_path
      },
      {
        name: "custom_code.yml",
        path: "global/custom_code.yml",
        type: "custom_code",
        description: "Add any HTML/JS/CSS into your site's <head> or footer",
        edit_path: admin_edit_custom_code_config_path
      },
      {
        name: "fonts.yml",
        path: "global/fonts.yml",
        type: "fonts",
        description: "Custom font configuration",
        edit_path: admin_edit_fonts_config_path
      }
    ]

    global_files << {
      name: "security.yml",
      path: "global/security.yml",
      type: "security",
      description: "rate limits for sign-in, sign-up and tokens",
      edit_path: admin_edit_security_config_path
    }

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
        description: "Only needed if you're developing Roe itself.",
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
        description: "Member payments and newsletter settings",
        edit_path: admin_edit_members_config_path
      }
    end

    if File.exist?(SiteConfig::FEATURES_PATH.join("podcast.yml"))
      features_files << {
        name: "podcast.yml",
        path: "features/podcast.yml",
        type: "features/podcast",
        description: "Add, edit, remove podcasts",
        edit_path: admin_edit_podcast_config_path
      }
    end

    if File.exist?(SiteConfig::FEATURES_PATH.join("store.yml"))
      features_files << {
        name: "store.yml",
        path: "features/store.yml",
        type: "features/store",
        description: "Currency, domain, categories, product groups",
        edit_path: admin_edit_store_config_path
      }
    end

    if File.exist?(SiteConfig::FEATURES_PATH.join("feeds.yml"))
      features_files << {
        name: "feeds.yml",
        path: "features/feeds.yml",
        type: "features/feeds",
        description: "Custom RSS/Atom feeds.",
        edit_path: admin_edit_feeds_config_path
      }
    end

    if File.exist?(SiteConfig::FEATURES_PATH.join("music.yml"))
      features_files << {
        name: "music.yml",
        path: "features/music.yml",
        type: "features/music",
        description: "Music releases.",
        edit_path: admin_edit_music_config_path
      }
    end

    # Default configs
    defaults_files = [
      {
        name: "cards.yml",
        path: "defaults/cards.yml",
        type: "defaults/cards",
        description: "post-link, aside, pullquote, templates",
        edit_path: admin_edit_cards_config_path
      },
      {
        name: "collections.yml",
        path: "defaults/collections.yml",
        type: "defaults/collections",
        description: "source, post-type, order, limit, template",
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

    # Shown whenever members are on. Sign-in emails go through this whether or
    # not the site ever sends a newsletter, so gating it on newsletters left the
    # one setting a members-only site needs hidden from it.
    if SiteFeature.email_feature_enabled?
      integration_files << {
        name: "postmark.yml",
        path: "integrations/postmark.yml",
        description: "Email delivery — sign-in links, confirmations, newsletters",
        edit_path: admin_edit_newsletters_config_path,
        unconfigured: SiteFeature.email_unconfigured?
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
    # Active-theme dropdown options must include any custom theme the
    # user has installed (e.g. roe-site), not just the bundled ones
    # the schema hardcodes. Without this, the user's actual active
    # theme can't be shown as selected, and saving the site config
    # would clear it.
    @available_themes = list_available_themes
    # Measure the saved social image so the branding section can warn
    # when its aspect ratio is off (square logos letterbox on
    # Facebook/LinkedIn/Slack; the recommended 1200×630 is ~1.91:1).
    @social_image_warning = social_image_ratio_warning(@config_hash["social_image"])
    render :edit
  end

  # Returns a human-readable warning string when the configured social
  # image's aspect ratio is outside the recommended landscape window,
  # or nil when it's fine / unmeasurable / blank. Pure advisory — never
  # blocks a save.
  def social_image_ratio_warning(image_ref)
    ref = image_ref.to_s.strip
    return nil if ref.empty?

    if ref.downcase.end_with?(".svg")
      return "This is an SVG. Social platforms reject vector images for cards — use a 1200×630 JPG or PNG instead."
    end

    dims = ImageDimensions.for_url(ref)
    return nil unless dims && dims[:height].to_i.positive?

    ratio = dims[:width].to_f / dims[:height]
    # ~1.91:1 is the target. Allow a generous landscape band; warn
    # outside it. Square-ish images still work on Twitter (we adapt the
    # card type) but get letterboxed elsewhere — hence the warning.
    return nil if ratio.between?(1.7, 2.2)

    shape = ratio < 1.0 ? "portrait" : (ratio.between?(0.8, 1.25) ? "square" : "non-standard")
    "Your social image is #{dims[:width]}×#{dims[:height]} (#{shape}). For best results across Facebook, LinkedIn, and Slack, use 1200×630. Twitter will still render it as a #{ratio.between?(0.8, 1.25) ? 'compact square' : 'large'} card."
  end

  def update_site
    update_config("site", SiteConfig::SITE_FILE)
  end

  # GET — security.yml. Rate limits for the public endpoints, one section per
  # limit. The file is written on first save; until then the form shows the
  # defaults that are already in force, so what's on screen is what's running.
  def edit_security
    @config_type = "security"
    @config_content = File.exist?(SiteConfig::SECURITY_FILE) ? File.read(SiteConfig::SECURITY_FILE) : ""
    @config_hash = (YAML.safe_load(@config_content) if @config_content.present?) || {}
    @config_schema = SECURITY_CONFIG_SCHEMA
    @available_themes = []
    render :edit
  end

  def update_security
    update_config("security", SiteConfig::SECURITY_FILE)
  end

  # GET — dedicated edit page for content.yml (rendering + search), split
  # out of site.yml. Reuses the schema-driven config editor.
  def edit_content
    @config_type = "content"
    @config_content = File.exist?(SiteConfig::CONTENT_FILE) ? File.read(SiteConfig::CONTENT_FILE) : ""
    @config_hash = (YAML.safe_load(@config_content, permitted_classes: [ Date, Time, Symbol ]) if @config_content.present?) || {}
    @config_schema = CONTENT_CONFIG_SCHEMA
    @available_themes = []
    render :edit
  end

  def update_content
    update_config("content", SiteConfig::CONTENT_FILE)
  end

  # GET — focused edit page for custom_code.yml. Loads the three
  # fields: themes (scoping array), head_html, footer_html. Also
  # surfaces @available_themes so the multi-select can render
  # checkboxes for every theme the install knows about. When the
  # file doesn't exist yet (first-time editors before any save),
  # falls back to empty values.
  def edit_custom_code
    config = SiteConfig.custom_code || {}
    @themes      = Array(config["themes"])
    @head_html   = config["head_html"].to_s
    @footer_html = config["footer_html"].to_s
    @available_themes = list_installed_themes
  end

  # POST — writes the three fields back to custom_code.yml. Creates
  # the file on first save (the SiteTemplates loader's auto-install
  # only runs at boot for fresh installs; existing installs that
  # pre-date the file get it on their first save here).
  #
  # YAML.dump prefixes a `---\n` document marker that the rest of
  # Roe's config files don't carry — strip it so the file stays
  # consistent with site.yml, fonts.yml, etc.
  def update_custom_code
    config = {
      "themes"      => Array(params[:themes]).reject(&:blank?),
      "head_html"   => params[:head_html].to_s,
      "footer_html" => params[:footer_html].to_s
    }

    FileUtils.mkdir_p(File.dirname(SiteConfig::CUSTOM_CODE_FILE))
    File.write(SiteConfig::CUSTOM_CODE_FILE, config.to_yaml.sub(/\A---\s*\n/, ""))
    SiteConfig.sync_from_file("custom_code")
    Rails.cache.clear

    flash[:notice] = "Custom code saved."
    redirect_to admin_edit_custom_code_config_path
  end

  # Enable custom feeds by creating features/feeds.yml, seeded with one example
  # feed so the format is clear. Idempotent — if the file already exists, just
  # open the editor.
  def new_feeds_setup
    unless File.exist?(FeedConfig::FILE)
      FileUtils.mkdir_p(File.dirname(FeedConfig::FILE))
      File.write(FeedConfig::FILE, <<~YAML)
        articles:
          title: Articles
          source: posts
          post_type: article
          order: date
          limit: 20
          audience: free
      YAML
      SiteConfig.sync_from_file("features/feeds")
      flash[:notice] = "Custom feeds enabled. Edit feeds.yml below to define your feeds."
    end
    redirect_to admin_edit_feeds_config_path
  end

  def edit_feeds
    unless File.exist?(FeedConfig::FILE)
      redirect_to admin_configs_path, alert: "Custom feeds aren't enabled yet." and return
    end
    @config_content = File.read(FeedConfig::FILE)
    render :edit_feeds
  end

  # Raw-YAML save. Validate the document is a mapping (feed name → settings)
  # before writing — a broken file would take down every named feed — and
  # re-render with the user's input intact on any parse error.
  def update_feeds
    content = params[:content].to_s.gsub(/\r\n/, "\n")

    parsed = YAML.safe_load(content)
    unless parsed.nil? || parsed.is_a?(Hash)
      @config_content = content
      flash.now[:alert] = "feeds.yml must be a mapping of feed name to settings."
      return render(:edit_feeds, status: :unprocessable_entity)
    end

    File.write(FeedConfig::FILE, content)
    SiteConfig.sync_from_file("features/feeds")
    flash[:notice] = "Feeds saved."
    redirect_to admin_configs_path
  rescue Psych::SyntaxError => e
    @config_content = content
    flash.now[:alert] = "YAML error: #{e.message}"
    render(:edit_feeds, status: :unprocessable_entity)
  end

  # Enable music by installing lib/site_templates/features/music/, which seeds
  # features/music.yml with an example release — the same path members, store
  # and podcast take, so the template is the one place the starting file is
  # defined. The loader skips files that already exist, and the guard keeps the
  # "enabled" flash for the run that actually creates it.
  def new_music_setup
    unless File.exist?(ReleaseConfig::FILE)
      SiteTemplates::Loader.install(folder: "features/music")
      SiteConfig.sync_from_file("features/music")
      flash[:notice] = "Music enabled. Edit music.yml below to define your releases."
    end
    redirect_to admin_edit_music_config_path
  end

  def edit_music
    unless File.exist?(ReleaseConfig::FILE)
      redirect_to admin_configs_path, alert: "Music isn't enabled yet." and return
    end
    load_music_config
    render :edit_music
  end

  # Save from the structured form. `content` is only present when the admin
  # used the YAML toggle, and takes precedence — that's the escape hatch for
  # anything the form can't express.
  def update_music
    return update_music_from_yaml if params[:content].present?

    globals = params.fetch(:music_globals, {}).permit!.to_h
    posted  = params.fetch(:releases, {}).permit!.to_h.values

    config = globals.filter_map { |k, v| [ k, v.to_s.strip ] if v.to_s.strip.present? }.to_h
    releases = {}
    posted.each do |row|
      key = release_key_for(row)
      next if key.blank?
      fields = MusicConfigSchema::RELEASE_KEYS.filter_map do |f|
        value = row[f].to_s.strip
        # The feed checkbox posts "true"/"false". Store it as a real boolean,
        # and leave a false one out entirely so the file only carries what's
        # actually switched on.
        next [ f, true ] if f == "feed" && ReleaseConfig.truthy?(value)
        next nil if f == "feed"
        [ f, value ] if value.present?
      end.to_h
      # A row with nothing but a key is a release the admin added and left
      # empty; keep it rather than silently dropping their click.
      releases[key] = fields
    end
    config["releases"] = releases

    write_music_config(config)
    flash[:notice] = "Music saved."
    redirect_to admin_edit_music_config_path
  end

  # Raw YAML editor — the escape hatch a structured editor redirects to when its
  # file won't parse. Shows the file as-is so the admin can fix it by hand.
  def edit_raw
    @raw_type = params[:type].to_s
    return redirect_to(admin_configs_path, alert: "Unknown config file.") unless RAW_EDITABLE_CONFIGS.value?(@raw_type)

    path = SiteConfig.file_path_for(@raw_type)
    @config_content = File.exist?(path) ? File.read(path) : ""
    @structured_path = structured_edit_path(@raw_type)
    render :edit_raw
  end

  def update_raw
    @raw_type = params[:type].to_s
    return redirect_to(admin_configs_path, alert: "Unknown config file.") unless RAW_EDITABLE_CONFIGS.value?(@raw_type)

    content = params[:content].to_s.gsub(/\r\n/, "\n")
    YAML.load(content) # raises Psych::SyntaxError if it still won't parse

    path = SiteConfig.file_path_for(@raw_type)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    SiteConfig.sync_from_file(@raw_type)
    redirect_to structured_edit_path(@raw_type), notice: "Saved. The settings form should open now."
  rescue Psych::SyntaxError => e
    @config_content = content
    @structured_path = structured_edit_path(@raw_type)
    flash.now[:alert] = "Still invalid YAML: #{e.message}"
    render(:edit_raw, status: :unprocessable_entity)
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

  # Themes that are actually INSTALLED on this site (present in
  # /site/theme/, regardless of whether they're a copy of a bundled
  # one or a hand-rolled custom). Used by Custom Code's theme
  # multi-select — bundled-but-not-installed themes can't be the
  # active theme, so scoping to them would never match.
  def list_installed_themes
    user_dir = File.join(RoeSitePaths::SITE_PATH, "theme")
    return [] unless Dir.exist?(user_dir)
    Dir.glob(File.join(user_dir, "*.css")).map { |f| File.basename(f, ".css") }.sort
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

    # Auto-surface the subscribe app/service links + display toggle on
    # every podcast block, so admins can always manage them even for
    # shows seeded before these fields existed. Same idea as `audience`
    # above: empty keys become visible "fill me in" inputs; blanks stay
    # hidden on the public page.
    @config_hash.each do |key, podcast|
      next unless podcast.is_a?(Hash)
      PodcastConfig::SUBSCRIBE_APPS.each_key do |field|
        podcast[field] = "" unless podcast.key?(field)
      end
      podcast["subscribe_display"] = "links" unless podcast.key?("subscribe_display")
    end

    # Order each podcast's fields so the subscribe group renders last, with the
    # display toggle first — the editor draws a single "Subscribe Links"
    # heading over them (see _config_editor).
    subscribe_order = [ "subscribe_display" ] + PodcastConfig::SUBSCRIBE_APPS.keys
    @config_hash.each_key do |key|
      podcast = @config_hash[key]
      next unless podcast.is_a?(Hash)
      reordered = podcast.reject { |k, _| PodcastConfig::SUBSCRIBE_FIELDS.include?(k) }
      subscribe_order.each { |k| reordered[k] = podcast[k] if podcast.key?(k) }
      @config_hash[key] = reordered
    end

    @field_options = build_field_options_for_podcast
    @field_help = build_field_help_for_podcast
    # Source of truth for which podcast fields are required (used by the
    # admin form to render the red asterisk next to the label).
    @field_required = PodcastConfig::REQUIRED_FIELDS
    # Per-show draft episode counts, so the Danger Zone can offer to delete a
    # show's drafts on removal. Published episodes are never touched here.
    @draft_episode_counts = draft_episode_counts_by_podcast
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
    # If the source was an Apple Podcasts link, fill the Apple + Overcast
    # subscribe fields from its iTunes ID too.
    subscribe = fetch.data[:apple_id] ? PodcastAppleLink.subscribe_links(fetch.data[:apple_id]) : {}
    seeder = PodcastConfigSeeder.new(key, channel.transform_keys(&:to_s), mode: :overwrite, subscribe_links: subscribe)
    result = seeder.seed!

    extra = subscribe.any? ? " Apple & Overcast links added." : ""
    redirect_to admin_edit_podcast_config_path,
                notice: "Podcast '#{title}' seeded as '#{key}' (#{result}).#{extra}"
  end

  def update_podcast
    update_config("features/podcast", SiteConfig::FEATURES_PATH.join("podcast.yml"))
  end

  def edit_cards
    @config_type = "cards"
    @config_content = File.read(SiteConfig::DEFAULTS_PATH.join("cards.yml"))
    @config_hash = YAML.load(@config_content) || {}
    @field_options = build_field_options_for_cards
    @field_help = build_field_help_for_cards

    # Settings added after an install was created aren't in its cards.yml.
    # Show them empty so they can be set, without writing to /site/ — the value
    # lands in the file only when the user saves. Same intent as
    # @extra_field_defaults in edit_collections, done here because these sit in
    # a nested section, which that mechanism doesn't reach.
    section = (@config_hash["post-link"] ||= {})
    %w[default_show_subtitle default_show_excerpt].each do |key|
      section[key] = "" unless section.key?(key)
    end

    @retired_settings = RetiredConfigSettings.in_config(@config_hash)
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
    # Fields the partial should render even when the install's YAML
    # doesn't contain them yet — lets us surface new settings added in
    # later releases without ever writing to /site/. Each entry maps a
    # key to its default value; the partial only renders entries whose
    # key isn't already in @config_hash. The default lands in the YAML
    # only when the user clicks save.
    @extra_field_defaults = { "pagination_template" => "list" }
    @retired_settings = RetiredConfigSettings.in_config(@config_hash)
    render :edit
  end

  def update_collections
    update_config("defaults/collections", SiteConfig::DEFAULTS_PATH.join("collections.yml"))
  end

  # Drop settings a Roe update stopped reading. Only ever runs on a click —
  # Roe doesn't rewrite files under site/ by itself, and nothing depends on
  # this having happened.
  CLEANUP_FILES = {
    "cards"       => "cards.yml",
    "collections" => "collections.yml"
  }.freeze

  def cleanup
    type = params[:type].to_s
    filename = CLEANUP_FILES[type]
    return redirect_to(admin_configs_path, alert: "Nothing to clean up there.") unless filename

    removed = RetiredConfigSettings.strip!(SiteConfig::DEFAULTS_PATH.join(filename))

    if removed.any?
      SiteConfig.sync_from_file("defaults/#{type}")
      flash[:notice] = "Removed #{removed.to_sentence} from #{filename}. Your defaults are unchanged."
    else
      flash[:notice] = "Nothing to remove — #{filename} is already up to date."
    end

    redirect_to type == "cards" ? admin_edit_cards_config_path : admin_edit_collections_config_path
  end

  def field_options_for(config_type, field_name)
    case [ config_type, field_name ]
    when [ "collections", "default_source" ]
      sources = [ "posts", "pages", "documentation" ]
      sources << "products" if SiteFeature.store_enabled?
      sources
    when [ "collections", "default_post_type" ]
      [ "all" ] + Post::POST_TYPES.keys.map(&:to_s)
    when [ "collections", "default_order" ]
      [ "date", "date-asc", "title", "filename" ]
    when [ "collections", "default_template" ]
      [ "list", "compact", "links", "full", "glossary" ]
    when [ "collections", "pagination_template" ]
      [ "list", "compact", "links", "full" ]
    when [ "collections", "items_per_page" ]
      [ "5", "10", "20", "25", "50", "100" ]
    when [ "cards", "default_style" ]
      [ "small", "medium", "large" ]
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
    # The config is gone, so there's nothing to sync from — release the
    # files its shows were protecting.
    Medium.recompute_for_config("features/podcast")

    flash[:notice] = "Podcast configuration deleted successfully"
    redirect_to admin_configs_path
  end

  # Delete a single podcast's entry from podcast.yml, leaving the others (and
  # the feature) in place. The show's posts are untouched. If it was the last
  # podcast, remove the whole config and disable the feature.
  def delete_podcast_entry
    key = params[:key].to_s
    file_path = SiteConfig::FEATURES_PATH.join("podcast.yml")

    unless File.exist?(file_path)
      redirect_to admin_configs_path, alert: "Podcast configuration doesn't exist." and return
    end

    config = YAML.load_file(file_path, permitted_classes: [ Date, Time ]) || {}
    unless config.is_a?(Hash) && config.key?(key)
      redirect_to admin_edit_podcast_config_path, alert: "Podcast '#{key}' not found." and return
    end

    title = config[key].is_a?(Hash) ? config[key]["title"].to_s.strip.presence : nil

    # Opt-in: also delete this show's DRAFT episodes (published ones are never
    # touched here — those are removed by hand). Done before the config write
    # so a failure leaves the show in place.
    deleted_drafts = params[:delete_drafts].present? ? delete_draft_episodes(key) : 0
    drafts_note = deleted_drafts.positive? ? " and #{helpers.pluralize(deleted_drafts, 'draft episode')}" : ""

    config.delete(key)

    if config.empty?
      File.delete(file_path)
      SiteConfig.find_by("file_path LIKE ?", "%podcast.yml")&.destroy
      SiteConfig.reload!("features/podcast")
      # The config is gone, so there's nothing to sync from — release the
      # files its shows were protecting.
      Medium.recompute_for_config("features/podcast")
      redirect_to admin_configs_path,
                  notice: "Removed “#{title || key}”#{drafts_note}. That was the last podcast, so podcasts are now disabled."
    else
      File.write(file_path, config.to_yaml.sub(/\A---\s*\n/, ""))
      # sync, not just reload: removing a show drops the audience its episodes
      # were inheriting, so their files have to be re-resolved.
      SiteConfig.sync_from_file("features/podcast")
      redirect_to admin_edit_podcast_config_path, notice: "Removed podcast “#{title || key}”#{drafts_note}."
    end
  end

  # Append a fresh blank podcast entry to podcast.yml (canonical defaults) so
  # the admin can fill it in — the manual counterpart to "Seed from feed".
  def add_podcast
    file_path = SiteConfig::FEATURES_PATH.join("podcast.yml")
    unless File.exist?(file_path)
      redirect_to admin_configs_path, alert: "Enable podcasts before adding a show." and return
    end

    config = YAML.load_file(file_path, permitted_classes: [ Date, Time ]) || {}
    config = {} unless config.is_a?(Hash)

    base = "new-podcast"
    key = base
    n = 1
    while config.key?(key)
      n += 1
      key = "#{base}-#{n}"
    end
    config[key] = PodcastConfig.default_entry

    File.write(file_path, config.to_yaml.sub(/\A---\s*\n/, ""))
    SiteConfig.sync_from_file("features/podcast")
    redirect_to admin_edit_podcast_config_path(tab: key),
                notice: "Added a new podcast (“#{key}”). Rename its key and fill in the details below."
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
    # The store form rebuilds store.yml from its own fields, dropping
    # product_groups (a read-only, derived registry). Re-derive it from the
    # products so the group list and the editor autocomplete survive the save.
    ProductGroup.resync_registry
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
    flash[:notice] = "Registry token cleared."
    redirect_to admin_edit_deploy_config_path
  end

  def edit_deploy
    @config_hash         = File.exist?(SiteConfig::DEPLOY_FILE) ? (YAML.load_file(SiteConfig::DEPLOY_FILE) || {}) : {}
    @deploy_secrets      = DeploySecrets.current
    @master_key_present  = DeployConfigGenerator.master_key_present?
    @fly_cli_available   = DeployConfigGenerator.fly_cli_available?
    # Only asked when the CLI exists and Fly is the target: it's a network round
    # trip to Fly's API, and asking without a `fly` binary would report "not
    # signed in", sending someone to log in to a tool they haven't installed.
    @fly_signed_in       = @fly_cli_available && fly_target? ? DeployPreflight.new.fly_authenticated? : true
    @kamal_cli_available = DeployConfigGenerator.kamal_cli_available?
    @site_size_bytes     = site_size_bytes
    # Local SSH keys for the kamal.ssh picker. Kamal supports an array
    # of identity files but we only surface single-pick — easier UX,
    # and 99% of users have one key per host anyway.
    @ssh_keys            = SshKeyInspector.list
    render :edit_deploy
  end

  def update_deploy
    dp = params[:deploy_config] || {}

    # Single SSH-key picker writes to kamal.ssh.keys (Kamal's native
    # array shape) so `kamal deploy` and our own rsync invocations
    # both read the same path. Empty selection drops the ssh block
    # entirely so Kamal falls back to its defaults.
    kamal_block = {
      "servers"           => (dp.dig(:kamal, :servers) || []).reject(&:blank?),
      "registry_username" => dp.dig(:kamal, :registry_username).to_s.strip,
      "image_name"        => dp.dig(:kamal, :image_name).to_s.strip,
      "host"              => dp.dig(:kamal, :host).to_s.strip
    }
    # SSH key lives in Common Settings (mentally global), serialized
    # under the kamal block in the YAML because that's where the
    # generated Kamal deploy.yml expects it.
    chosen_key = dp[:ssh_key].to_s.strip
    if chosen_key.present?
      kamal_block["ssh"] = { "keys" => [ chosen_key ], "keys_only" => true }
    end

    config = {
      "target"   => dp[:target].to_s.presence || "kamal",
      "app_name" => dp[:app_name].to_s.strip,
      "ssl"      => dp[:ssl] == "1",
      "kamal"    => kamal_block,
      "fly"      => {
        "region"         => dp.dig(:fly, :region).to_s.strip,
        "vm_memory"      => dp.dig(:fly, :vm_memory).to_s.strip,
        "volume_size_gb" => dp.dig(:fly, :volume_size_gb).to_i
      }
    }

    FileUtils.mkdir_p(File.dirname(SiteConfig::DEPLOY_FILE))
    write_yaml(SiteConfig::DEPLOY_FILE, config)
    SiteConfig.sync_from_file("deploy")

    # Save registry token if a new one was provided (blank = keep existing).
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
    # Only asked when the CLI exists and Fly is the target: it's a network round
    # trip to Fly's API, and asking without a `fly` binary would report "not
    # signed in", sending someone to log in to a tool they haven't installed.
    @fly_signed_in       = @fly_cli_available && fly_target? ? DeployPreflight.new.fly_authenticated? : true
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

    @config_type    = "development"
    @config_content = File.read(development_config_path)
    @config_hash    = YAML.load(@config_content) || {}
    @allowed_hosts  = @config_hash["allowed_hosts"] || []
    @dev_host       = @config_hash["dev_host"].to_s
    render :edit_development
  end

  def update_development
    hosts    = params[:allowed_hosts]&.reject(&:blank?) || []
    dev_host = params[:dev_host].to_s.strip

    # Merge into the existing hash so any keys the form doesn't
    # manage (future settings the user has hand-edited in, comments
    # we wouldn't preserve through round-tripping, etc.) survive
    # the round trip. We let Hash#to_yaml own the serialisation —
    # this file is admin-managed-only, no user-authored formatting
    # to preserve.
    existing = File.exist?(SiteConfig::DEVELOPMENT_FILE) ? (YAML.load(File.read(SiteConfig::DEVELOPMENT_FILE)) || {}) : {}
    existing["allowed_hosts"] = hosts
    if dev_host.empty?
      existing.delete("dev_host")
    else
      existing["dev_host"] = dev_host
    end

    File.write(SiteConfig::DEVELOPMENT_FILE, existing.to_yaml)
    SiteConfig.sync_from_file("development")

    flash[:notice] = "Development configuration updated successfully"
    redirect_to admin_configs_path
  rescue => e
    flash.now[:error] = "Failed to update configuration: #{e.message}"
    @config_type    = "development"
    @config_content = File.read(SiteConfig::DEVELOPMENT_FILE)
    @config_hash    = YAML.load(@config_content) || {}
    @allowed_hosts  = @config_hash["allowed_hosts"] || []
    @dev_host       = @config_hash["dev_host"].to_s
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
      # Create development.yml with default content.
      #
      # `allowed_hosts` feeds Rails' Host Authorization so requests
      # coming in from a tunnel hostname aren't rejected. The first
      # public-looking entry here is also what WebhookUrlHelper
      # uses as the dev webhook callback host (so Stripe / Postmark
      # webhooks point at your tunnel instead of localhost).
      #
      # `dev_host` is an explicit override — set it if you want a
      # different host for webhook callbacks than the first entry
      # in allowed_hosts (e.g. multiple tunnels for different
      # purposes). Commented out by default; most setups don't need
      # it because the allowed_hosts fallback works.
      FileUtils.mkdir_p(SiteConfig::DEVELOPMENT_FILE.dirname)
      File.write(SiteConfig::DEVELOPMENT_FILE, <<~YAML)
        allowed_hosts:
          - your-site.ngrok-free.app

        # dev_host: your-site.ngrok-free.app
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
    redirect_to admin_edit_payments_config_path(tab: "test")
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
    redirect_to admin_edit_payments_config_path(tab: "live")
  end

  def update_payments_mode
    update_integration_mode(StripeConfig.current, "Payments")
    # Reopen the tab matching the now-active mode (the tabs controller reads
    # ?tab= on load). Falls back to the current mode if the switch was rejected.
    redirect_to admin_edit_payments_config_path(tab: StripeConfig.current.mode)
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
    redirect_to admin_edit_newsletters_config_path(tab: "test")
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
    redirect_to admin_edit_newsletters_config_path(tab: "live")
  end

  def update_newsletters_mode
    update_integration_mode(PostmarkConfig.current, "Email")
    redirect_to admin_edit_newsletters_config_path(tab: PostmarkConfig.current.mode)
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
    # The snippet is public and shown in full (never masked), so save it
    # verbatim — a blank submission means "clear it," not "leave unchanged."
    existing["test"]["snippet"] = test_data["snippet"].to_s

    write_yaml(path, existing)
    SiteConfig.sync_from_file("integrations/snipcart")

    SnipcartConfig.save_test_config(existing["test"])
    SnipcartConfig.current.verify!

    flash[:notice] = "Store (Snipcart) Test configuration saved"
    redirect_to admin_edit_snipcart_integration_config_path(tab: "test")
  end

  def update_snipcart_live
    # The live snippet carries only a PUBLIC key, so — unlike Stripe/Postmark
    # live keys — it's saved locally too: the same snippet runs the local
    # store AND the static-site build (no production server needed). There's
    # no secret key; webhooks (a future production concern) use Snipcart's
    # per-request token, not a stored secret.
    # Save the snippet verbatim — including blank, so clearing the field
    # removes it (it's public and shown in full, never masked).
    SnipcartConfig.save_live_snippet(params[:live][:snippet].to_s) if params[:live]

    SnipcartConfig.current.verify!
    flash[:notice] = "Snipcart Live & Static Site configuration saved"
    # Pin the Live/Static Site tab so the page reopens where the user was
    # (the tabs Stimulus controller reads ?tab= on load).
    redirect_to admin_edit_snipcart_integration_config_path(tab: "live")
  end

  def update_snipcart_mode
    update_integration_mode(SnipcartConfig.current, "Store")
    redirect_to admin_edit_snipcart_integration_config_path(tab: SnipcartConfig.current.mode)
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
      error:       success ? nil : "No Snipcart snippet found. Paste your snippet and save."
    }
  end

  private

  # rescue_from handler: a structured editor couldn't parse its file. Route the
  # admin to the raw editor for that config; re-raise for anything unmapped.
  def handle_unparseable_config(error)
    type = RAW_EDITABLE_CONFIGS[action_name]
    raise error unless type

    redirect_to admin_edit_raw_config_path(type: type),
      alert: "This config file has a YAML error, so its settings form can't open. Fix the raw YAML below and save. (#{error.message})"
  end

  # The structured edit path for a raw-editable config type. Every one follows
  # admin_<action>_config_path, so derive it from the action in the map.
  def structured_edit_path(type)
    action = RAW_EDITABLE_CONFIGS.key(type)
    send("admin_#{action}_config_path")
  end

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

  # Write podcast.yml as a single-entry file. Builds the YAML by hand
  # rather than round-tripping through `Hash#to_yaml` so the output
  # quoting matches what the admin config editor's formToYaml emits:
  # strings always wrapped in `""` (including empty strings), boolean
  # values unquoted, arrays in block style. Round-tripping through
  # Psych would otherwise produce `''` for empty strings, bare
  # unquoted values for safe identifiers like "Business", and
  # flow-style arrays — every save would oscillate between two
  # different formats depending on which entry point wrote it.
  def write_single_podcast_entry(key, data)
    path = SiteConfig::FEATURES_PATH.join("podcast.yml")
    FileUtils.mkdir_p(File.dirname(path))

    lines = [ "#{key}:" ]
    data.each do |field, value|
      lines << format_yaml_field(field, value, indent: 1)
    end

    File.write(path, lines.join("\n") + "\n")
  end

  # Draft podcast episodes belonging to a given show (never published ones).
  def draft_episodes_for(key)
    Post.where("json_extract(metadata, '$.post_type') = ?", "podcast")
        .where("json_extract(metadata, '$.podcast') = ?", key.to_s)
        .where("json_extract(metadata, '$.status') = ?", "draft")
  end

  # Delete a show's draft episodes — both the markdown file and the DB record,
  # mirroring the posts controller's destroy. Returns how many were removed.
  def delete_draft_episodes(key)
    count = 0
    draft_episodes_for(key).find_each do |post|
      File.delete(post.file_path) if post.file_path.present? && File.exist?(post.file_path)
      post.destroy
      count += 1
    end
    count
  end

  # { podcast_key => draft_episode_count } across all shows, in one query.
  def draft_episode_counts_by_podcast
    Post.where("json_extract(metadata, '$.post_type') = ?", "podcast")
        .where("json_extract(metadata, '$.status') = ?", "draft")
        .group("json_extract(metadata, '$.podcast')")
        .count
  end

  # Format a single YAML field at the given indentation level.
  # Mirrors the JS `simpleYamlStringify` + `formatYamlValue` rules:
  #   - true/false (Ruby) and "true"/"false" strings → unquoted
  #     YAML boolean
  #   - Integer/numeric strings → unquoted
  #   - Arrays → block style, empty stays `[]`
  #   - Everything else → double-quoted string, even when empty
  def format_yaml_field(key, value, indent:)
    spaces = "  " * indent

    case value
    when Array
      return "#{spaces}#{key}: []" if value.empty?

      block = [ "#{spaces}#{key}:" ]
      child_spaces = "  " * (indent + 1)
      value.each do |v|
        block << %(#{child_spaces}- "#{v.to_s.gsub('"', '\\"')}")
      end
      block.join("\n")
    when TrueClass, FalseClass
      "#{spaces}#{key}: #{value}"
    when nil
      %(#{spaces}#{key}: "")
    else
      str = value.to_s
      if str == "true" || str == "false"
        "#{spaces}#{key}: #{str}"
      elsif str.match?(/\A-?\d+(\.\d+)?\z/)
        "#{spaces}#{key}: #{str}"
      else
        escaped = str.gsub('"', '\\"')
        %(#{spaces}#{key}: "#{escaped}")
      end
    end
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
      "category_secondary" => [
        "",
        "Arts", "Business", "Comedy", "Education", "Fiction", "Government",
        "Health & Fitness", "History", "Kids & Family", "Leisure", "Music",
        "News", "Religion & Spirituality", "Science", "Society & Culture",
        "Sports", "Technology", "True Crime", "TV & Film"
      ],
      # Note: subcategory/subcategory_secondary are arrays, handled by JS
      "language" => [ "en", "es", "fr", "de", "it", "pt", "ja", "zh", "ko", "ru" ],
      "explicit" => [ "false", "true" ],
      "episode_type" => [ "full", "trailer", "bonus" ],
      # Per-podcast audience gate. Renders as a select when the field is
      # present (auto-surfaced above when payments are enabled).
      "audience" => [ "everyone", "paid" ],
      # How the subscribe section renders on the episode page.
      "subscribe_display" => [ "links", "button + menu" ]
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
      "default_source" => [ "posts", "pages", "documentation" ] + (SiteFeature.store_enabled? ? [ "products" ] : []),
      "default_post_type" => [ "all" ] + existing_post_types,
      "default_order" => [ "date", "date-asc", "title", "filename" ],
      "default_template" => [ "list", "compact", "links", "full", "glossary" ],
      "pagination_template" => [ "list", "compact", "links", "full" ],
      "items_per_page" => [ "10", "20", "25", "50", "100" ]
    }
  end

  def build_field_options_for_cards
    {
      "post-link.default_style" => [ "small", "medium", "large" ],
      "post-link.default_show_subtitle" => [ "", "true", "false" ],
      "post-link.default_show_excerpt" => [ "", "true", "false" ],
      "pullquote.default_position" => [ "center", "left", "right" ]
    }
  end

  def build_field_help_for_cards
    {
      "post-link.default_show_subtitle" => {
        title: "Show subtitle",
        text: ("Leave blank and the card's style decides — off for small, on for medium and large. " \
               "Set it to have every post-link show or hide the subtitle whatever its style.<br><br>" \
               "A card can still override this with <code>show_subtitle:</code>.").html_safe
      },
      "post-link.default_show_excerpt" => {
        title: "Show excerpt",
        text: ("Leave blank and the card's style decides — on for large only. " \
               "Set it to have every post-link show or hide the excerpt whatever its style.<br><br>" \
               "A card can still override this with <code>show_excerpt:</code>.").html_safe
      }
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
      },
      "subscribe_display" => {
        title: "Subscribe display",
        text: ("<strong>links</strong> — show every subscribe link (Apple, Spotify, RSS…) inline on the episode page.<br><br>" \
               "<strong>button + menu</strong> — collapse them behind a single <em>Subscribe</em> button that opens on click.").html_safe
      },
      "apple_podcasts" => {
        title: "Subscribe links",
        text: ("Paste your show's page URL on each platform. Leave any blank to hide it. The public RSS feed (and the private paid feed, if applicable) are added automatically.").html_safe
      }
    }
  end

  # The saved target, so the Fly session check only runs on a Fly site.
  def fly_target?
    config = File.exist?(SiteConfig::DEPLOY_FILE) ? (YAML.load_file(SiteConfig::DEPLOY_FILE) || {}) : {}
    (config["target"].presence || "kamal").to_s == "fly"
  rescue StandardError
    false
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
      "newsletter.enabled" => "Enable newsletter sending via Postmark (requires Postmark account & configuration)",
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

    # Validate YAML syntax. safe_load (not load) so pasted config can't
    # instantiate arbitrary Ruby objects. The permitted classes cover the
    # scalar types YAML auto-converts (an unquoted date/time/symbol in a
    # config value); aliases stay allowed. Disallowed types raise a
    # Psych::Exception too, so they surface as a friendly error, not a 500.
    begin
      new_config = YAML.safe_load(content, permitted_classes: [ Date, Time, Symbol ], aliases: true)
    rescue Psych::Exception => e
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

    when "features/members"
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

    when "content"
      Rails.cache.clear
      flash[:notice] = "Content configuration updated successfully"

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

  def music_config_hash
    parsed = YAML.safe_load(File.read(ReleaseConfig::FILE), permitted_classes: [ Date, Time ])
    parsed.is_a?(Hash) ? parsed : {}
  rescue Psych::SyntaxError
    {}
  end

  def write_music_config(config)
    File.write(ReleaseConfig::FILE, config.to_yaml.sub(/\A---\n/, ""))
    SiteConfig.sync_from_file("features/music")
  end

  # The key input lets an admin rename a release. Blank means "keep the one it
  # already had"; a brand-new row with no key falls back to its title.
  def release_key_for(row)
    typed = row["key"].to_s.strip.parameterize
    return typed if typed.present?
    row["original_key"].to_s.strip.presence || row["title"].to_s.strip.parameterize.presence
  end

  def load_music_config
    @config_content = File.read(ReleaseConfig::FILE)
    @config_hash    = music_config_hash
    raw             = @config_hash["releases"]
    @releases       = raw.is_a?(Hash) ? raw : {}
    # Every schema field present so the form draws an input for each, blank or
    # not — a missing key would render nothing and look like the field doesn't
    # exist. Same reason edit_podcast backfills its own.
    @releases = @releases.transform_values do |r|
      MusicConfigSchema.blank_release.merge(r.is_a?(Hash) ? r.transform_values(&:to_s) : {})
    end
    @image_paths = Medium.originals_only.where(media_type: "images").pluck(:file_path).sort
  end

  def update_music_from_yaml
    content = params[:content].to_s.gsub(/\r\n/, "\n")

    parsed = YAML.safe_load(content, permitted_classes: [ Date, Time ])
    unless parsed.nil? || parsed.is_a?(Hash)
      load_music_config
      @config_content = content
      flash.now[:alert] = "music.yml must be a mapping with a releases: block."
      return render(:edit_music, status: :unprocessable_entity)
    end

    File.write(ReleaseConfig::FILE, content)
    SiteConfig.sync_from_file("features/music")
    flash[:notice] = "Music saved."
    redirect_to admin_configs_path
  rescue Psych::SyntaxError => e
    load_music_config
    @config_content = content
    flash.now[:alert] = "YAML error: #{e.message}"
    render(:edit_music, status: :unprocessable_entity)
  end
end
