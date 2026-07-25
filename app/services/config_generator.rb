class ConfigGenerator
  SYSTEM_PATH       = File.join(RoeSitePaths::SITE_PATH, "system")
  SITE_PATH         = File.join(SYSTEM_PATH, "global")
  FEATURES_PATH     = File.join(SYSTEM_PATH, "features")
  DEFAULTS_PATH     = File.join(SYSTEM_PATH, "defaults")
  ASSETS_PATH       = File.join(SYSTEM_PATH, "assets")
  INTEGRATIONS_PATH = File.join(SYSTEM_PATH, "integrations")

  # ── Public class-method API (preserved for existing callers) ────────────

  def self.generate_all;          new.generate_all;                  end
  def self.generate_podcast;      new.generate_podcast_defaults;     end
  def self.generate_members;      new.generate_members_defaults;     end
  def self.generate_store;        new.generate_store_defaults;       end
  def self.generate_payments;     new.generate_payments_config;      end
  def self.generate_newsletters;  new.generate_newsletters_config;   end
  def self.generate_snipcart;     new.generate_snipcart_config;      end

  def self.generate_store_defaults(currency: "usd", default_domain: "", product_categories: [])
    new.generate_store_defaults(
      currency:           currency,
      default_domain:     default_domain,
      product_categories: product_categories,
    )
  end

  # ── Instance methods ────────────────────────────────────────────────────

  # Installs the "minimum" kit (site.yml, fonts.yml, cards.yml,
  # collections.yml, pages/home.md, posts/welcome.md). Safe to run on
  # every boot — the loader skips any file already in /site, so user
  # customizations stick. Also safe to re-run later with a different
  # kit (e.g. blog_kit) without overwriting anything.
  def generate_all
    ensure_directories

    result = SiteTemplates::Loader.install(
      folder:      "minimum",
      destination: RoeSitePaths::SITE_PATH,
      locals:      { today: Date.today },
      skip:        skip_paths_for_minimum,
    )

    result[:installed].each { |path| puts "✓ Installed #{path}" }

    migrate_content_config!
  end

  # One-time, idempotent migration for the site.yml → content.yml split.
  # Earlier versions kept these flat in site.yml; they now live in
  # content.yml (search nested). Move any that still linger in site.yml,
  # preserving the user's values, then strip them from site.yml. A no-op
  # once site.yml no longer holds them, so it's safe on every boot. Runs
  # AFTER the kit install above, so it overwrites the freshly-seeded
  # content.yml defaults with the user's real values.
  CONTENT_MIGRATION_MAP = {
    "search_all_pages"    => %w[search all_pages],
    "search_roe_docs"     => %w[search roe_docs],
    "results_when_opened" => %w[search results_when_opened],
    "soft_line_breaks"    => %w[soft_line_breaks]
  }.freeze

  def migrate_content_config!
    site_file    = SiteConfig::SITE_FILE
    content_file = SiteConfig::CONTENT_FILE
    return unless File.exist?(site_file)

    site = YAML.load_file(site_file) || {}
    stale = CONTENT_MIGRATION_MAP.keys.select { |k| site.key?(k) }
    return if stale.empty?

    content = (File.exist?(content_file) ? YAML.load_file(content_file) : {}) || {}
    stale.each do |old_key|
      *parents, leaf = CONTENT_MIGRATION_MAP[old_key]
      target = parents.reduce(content) { |h, k| h[k] ||= {} }
      target[leaf] = site.delete(old_key)
    end

    write_config_yaml(content_file, content)
    write_config_yaml(site_file, site)
    SiteConfig.sync_from_file("content")
    SiteConfig.sync_from_file("site")
    puts "✓ Migrated content settings (#{stale.join(', ')}) → content.yml"
  rescue => e
    Rails.logger.warn "[ConfigGenerator] content migration failed: #{e.class} #{e.message}"
  end

  # Match how Roe's other config writers emit YAML (no leading `---`).
  def write_config_yaml(path, data)
    File.write(path, YAML.dump(data).sub(/\A---\s*\n/, ""))
  end

  # Members. Three-step install:
  #   1. Render-and-WRITE members.yml — admin save intentionally
  #      overwrites with the new settings. This is the one file in the
  #      members feature whose entire purpose is to be rewritten.
  #   2. Loader installs pages + emails (skip-if-exists keeps any
  #      hand-edited copies). It tries members.yml too, but step 1 has
  #      already written it, so the existence check trips and it's
  #      skipped — no double write, no overwrite.
  #   3. Conditional integration drop-ins (Stripe / Postmark).
  def generate_members_defaults(show_paid_content: true, payments_enabled: false, payment_price: "0.00", newsletter_enabled: false)
    overwrite_from_template(
      folder:   "features/members",
      template: "system/features/members.yml.erb",
      target:   File.join(FEATURES_PATH, "members.yml"),
      locals: {
        payments_enabled:   payments_enabled,
        payment_price:      payment_price,
        newsletter_enabled: newsletter_enabled,
        show_paid_content:  show_paid_content
      },
    )

    install_folder("features/members")

    generate_payments_config    if payments_enabled
    generate_newsletters_config if newsletter_enabled
  end

  # Store. Same pattern as members: overwrite store.yml with the
  # admin's settings, then ensure the Snipcart integration drop-in.
  def generate_store_defaults(currency: "usd", default_domain: "", product_categories: [])
    categories = if product_categories.is_a?(String)
      product_categories.split(",").map(&:strip).map(&:downcase).reject(&:blank?)
    else
      Array(product_categories).map { |c| c.to_s.strip }.reject(&:empty?)
    end

    # YAML block fragment for `product_categories:`. Empty list emits
    # `[]` inline (the conventional empty-array form). Populated list
    # emits block-style with each entry on its own line, matching how
    # ProductCategory#rewritten_store_yaml_with_categories writes it
    # when a product save triggers a category-list update. Previously
    # the template baked the placeholder hint ("book, ebook, file")
    # into the file whenever the user left the modal field blank;
    # now blank = empty array = no preloaded categories.
    categories_yaml = if categories.empty?
      " []"
    else
      "\n" + categories.map { |c| %(  - "#{c.gsub('"', '\\"')}") }.join("\n")
    end

    overwrite_from_template(
      folder:   "features/store",
      template: "system/features/store.yml.erb",
      target:   File.join(FEATURES_PATH, "store.yml"),
      locals: {
        currency:        currency,
        default_domain:  default_domain,
        categories_yaml: categories_yaml
      },
    )

    generate_snipcart_config
  end

  # Podcast feed defaults. Pulls author/email/site_url from the
  # already-saved SiteConfig so the new podcast.yml inherits them
  # instead of forcing the user to re-enter the same values.
  def generate_podcast_defaults
    site_url         = (SiteConfig.get("url").presence && SiteConfig.site_url) || "https://yoursite.com"
    author           = SiteConfig.get("author").presence       || ""
    author_email     = SiteConfig.get("author_email").presence || "you@example.com"
    copyright_holder = author.presence || "Your Name"

    overwrite_from_template(
      folder:   "features/podcast",
      template: "system/features/podcast.yml.erb",
      target:   File.join(FEATURES_PATH, "podcast.yml"),
      locals: {
        author:           author,
        author_email:     author_email,
        site_url:         site_url,
        copyright_holder: copyright_holder,
        year:             Date.today.year
      },
    )
  end

  # Integration drop-ins — single static YAML files. Loader skips if
  # the file already has hand-edited credentials in it.
  def generate_payments_config;    install_folder("features/stripe");   end
  def generate_newsletters_config; install_folder("features/postmark"); end
  def generate_snipcart_config;    install_folder("features/snipcart"); end

  # Minimum-kit guard: if /site/posts/ already has any .md files, the
  # user has their own posts — don't drop welcome.md alongside them.
  # Without this, deleting welcome.md would have it reappear on every
  # boot.
  def skip_paths_for_minimum
    # The sidebar is opt-in: its template lives with the other layout files
    # (so it's the canonical default), but unlike header/footer it is never
    # auto-installed. The admin creates it on request via LayoutsController,
    # which renders this same template — see #generate_missing there.
    paths = [ "layout/sidebar.md" ]
    posts_dir = File.join(RoeSitePaths::SITE_PATH, "posts")
    if Dir.exist?(posts_dir) && Dir.glob(File.join(posts_dir, "*.md")).any?
      paths << "posts/welcome.md"
    end
    paths
  end

  private

  # Render an ERB template from a templates folder and write it to
  # `target`, overwriting whatever's there. Used for the admin-
  # controlled config files (members.yml, store.yml, podcast.yml) —
  # their whole job is to be rewritten each time the admin saves new
  # settings.
  def overwrite_from_template(folder:, template:, target:, locals:)
    rendered = SiteTemplates::Loader.render(folder: folder, template: template, locals: locals)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, rendered)
    relative = Pathname.new(target).relative_path_from(Pathname.new(RoeSitePaths::SITE_PATH))
    puts "✓ Generated #{relative}"
  end

  # Install every file from a templates folder, skip-if-exists. Thin
  # wrapper around SiteTemplates::Loader.install used by the small
  # feature / integration methods so they all share one install path.
  def install_folder(folder)
    result = SiteTemplates::Loader.install(
      folder:      folder,
      destination: RoeSitePaths::SITE_PATH,
    )
    result[:installed].each { |path| puts "✓ Installed #{path}" }
  end

  def ensure_directories
    FileUtils.mkdir_p(INTEGRATIONS_PATH)
    FileUtils.mkdir_p(SYSTEM_PATH)
    FileUtils.mkdir_p(SITE_PATH)
    FileUtils.mkdir_p(FEATURES_PATH)
    FileUtils.mkdir_p(DEFAULTS_PATH)
    FileUtils.mkdir_p(File.join(ASSETS_PATH, "fonts"))
    FileUtils.mkdir_p(File.join(ASSETS_PATH, "images"))
    # Note: 404.png (and the other default system images) ship in the
    # minimum kit and are seeded by SiteTemplates::Loader in generate_all,
    # so there's no separate copy step here anymore.
  end
end
