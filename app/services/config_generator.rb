class ConfigGenerator
  SYSTEM_PATH = File.join(RoeSitePaths::SITE_PATH, 'system')
  SITE_PATH = File.join(SYSTEM_PATH, 'global')
  FEATURES_PATH = File.join(SYSTEM_PATH, 'features')
  DEFAULTS_PATH = File.join(SYSTEM_PATH, 'defaults')
  ASSETS_PATH = File.join(SYSTEM_PATH, 'assets')
  INTEGRATIONS_PATH = File.join(SYSTEM_PATH, 'integrations')

  def self.generate_all
    new.generate_all
  end

  def self.generate_podcast
    new.generate_podcast_defaults
  end

  def generate_all
    ensure_directories
    generate_site_config unless File.exist?(File.join(SITE_PATH, 'site.yml'))
    generate_fonts_config unless File.exist?(File.join(SITE_PATH, 'fonts.yml'))
    generate_cards_defaults unless File.exist?(File.join(DEFAULTS_PATH, 'cards.yml'))
    generate_collections_defaults unless File.exist?(File.join(DEFAULTS_PATH, 'collections.yml'))
    generate_welcome_post
  end

  def generate_podcast_defaults
    # Pull sensible defaults from the existing site config so a brand-new
    # podcast.yml inherits the author, contact email, and site URL the
    # user has already set on the site as a whole. SiteConfig.site_url
    # normalizes (adds https:// when missing); the raw `url` key in
    # site.yml is what the user typed.
    site_url     = (SiteConfig.get('url').presence && SiteConfig.site_url) || 'https://yoursite.com'
    author       = SiteConfig.get('author').presence       || ''
    author_email = SiteConfig.get('author_email').presence || 'you@example.com'
    copyright_holder = author.presence || 'Your Name'

    content = <<~YAML
      # Podcast Configuration
      # Define one or more podcast feeds for your site

      my-podcast:
        title: "My Podcast"
        description: "A podcast about things"
        author: "#{author}"
        email: "#{author_email}"
        category: "Technology"
        subcategory: ""
        language: "en"
        copyright: "#{Date.today.year} #{copyright_holder}"
        explicit: false
        type: "episodic"
        artwork: ""
        link: "#{site_url}"
    YAML

    File.write(File.join(FEATURES_PATH, 'podcast.yml'), content)
    puts "✓ Generated features/podcast.yml"
  end

  def self.generate_members
      new.generate_members_defaults
    end

    def generate_members_defaults(show_paid_content: true, payments_enabled: false, payment_price: "0.00", newsletter_enabled: false)
      # Generate members.yml in features/
      content = <<~YAML
        payments:
          enabled: #{payments_enabled}
          mode: memberships
          price: "#{payment_price}"
          donation_amounts: [5, 10, 20, 50]
        newsletter:
          enabled: #{newsletter_enabled}
        everyone:
          show_paid_content: #{show_paid_content}
      YAML

      File.write(File.join(FEATURES_PATH, 'members.yml'), content)
      puts "✓ Generated features/members.yml"

      # Generate integration config files if features are enabled
      generate_payments_config if payments_enabled
      generate_newsletters_config if newsletter_enabled

    # Generate member pages
    generate_member_pages
  end

  def self.generate_store
    generate_store_defaults
  end

  def self.generate_payments
    new.generate_payments_config
  end

  def self.generate_newsletters
    new.generate_newsletters_config
  end

  def self.generate_snipcart
    new.generate_snipcart_config
  end

  def self.generate_store_defaults(currency: "usd", default_domain: "", product_categories: [])
    # Parse categories if it's a string
    categories = if product_categories.is_a?(String)
      product_categories.split(',').map(&:strip).map(&:downcase).reject(&:blank?)
    else
      product_categories || []
    end

    # Format categories for YAML output
    categories_string = categories.any? ? categories.join(', ') : 'book, ebook, file'

    content = <<~YAML
      enabled: true
      currency: "#{currency}"
      default_domain: "#{default_domain}"
      product_categories: "#{categories_string}"
      product_button_template: |
        ![Add Image Description](@image)

        # @title

        **Price:** @price

        @description

        ```button
        sku: @sku
        text: Add to Cart
        style: primary
        ```
      # Grouped product display settings
      grouped_products:
        button_text: "View"
        price_display: "range"  # Options: range, lowest, highest
        price_separator: "-"    # Separator between min/max prices in range mode
      snipcart:
        load_strategy: "on-user-interaction"
        modal_style: "side"
        show_taxes: true
        show_quantity: true
    YAML

    File.write(File.join(FEATURES_PATH, 'store.yml'), content)
    puts "✓ Generated features/store.yml"
    ConfigGenerator.new.generate_snipcart_config
  end

  def generate_payments_config
    path = File.join(INTEGRATIONS_PATH, 'payments.yml')
    return if File.exist?(path)

    content = <<~YAML
      # Stripe Test Keys
      # These keys are for testing only. Live keys are stored in the database.
      # Get your test keys from: https://dashboard.stripe.com/test/apikeys
      test:
        publishable_key: ""
        secret_key: ""
        webhook_signing_secret: ""
    YAML

    FileUtils.mkdir_p(INTEGRATIONS_PATH)
    File.write(path, content)
    puts "✓ Generated integrations/payments.yml"
  end

  def generate_newsletters_config
    path = File.join(INTEGRATIONS_PATH, 'newsletters.yml')
    return if File.exist?(path)

    content = <<~YAML
      # Postmark Test Token
      # This token is for testing only. The live token is stored in the database.
      # Get your server token from: https://account.postmarkapp.com/servers
      test:
        server_token: ""
    YAML

    FileUtils.mkdir_p(INTEGRATIONS_PATH)
    File.write(path, content)
    puts "✓ Generated integrations/newsletters.yml"
  end

  def generate_snipcart_config
    path = File.join(INTEGRATIONS_PATH, 'snipcart.yml')
    return if File.exist?(path)

    content = <<~YAML
      # Snipcart Configuration
      # Get your API keys from: https://app.snipcart.com/dashboard/account/credentials
      test:
        api_key: ""
    YAML

    FileUtils.mkdir_p(INTEGRATIONS_PATH)
    File.write(path, content)
    puts "✓ Generated integrations/snipcart.yml"
  end

  def generate_member_pages
    pages_path = File.join(RoeSitePaths::SITE_PATH, 'pages', 'members')
    FileUtils.mkdir_p(pages_path)

    generate_signup_page(pages_path)
    generate_signin_page(pages_path)
    generate_check_email_page(pages_path)
    generate_upgrade_page(pages_path)
    generate_donate_page(pages_path)
    generate_unsubscribe_page(pages_path)
    generate_unsubscribed_page(pages_path)

    # Generate email templates
    generate_member_emails
  end

  def generate_signup_page(pages_path)
    return if File.exist?(File.join(pages_path, 'signup.md'))

    signup_content = <<~MARKDOWN
      ---
      title: Sign Up
      url_name: sign-up
      status: published
      audience: everyone
      ---

      # Sign up for the newsletter

      It's free.

      ## What You Get

      - Newsletter to your inbox
      - No spam, ever[^1]

      ```form
      for: signup
      button-text: Free Account
      upgrade-button-text: Paid member
      ```

      Already have an account? [Sign in](/signin)

      [^1]: I will never sell your data either.
    MARKDOWN

    File.write(File.join(pages_path, 'signup.md'), signup_content)
    puts "✓ Generated members/signup.md page"
  end

  def generate_signin_page(pages_path)
    return if File.exist?(File.join(pages_path, 'signin.md'))

    signin_content = <<~MARKDOWN
      ---
      title: Sign In
      url_name: sign-in
      status: published
      audience: everyone
      ---

      # Welcome Back

      Sign in to access your account.

      **Free members:** You don't need a password - just enter your email.

      **Paid members:** Enter your email and password.

      ```form
      for: signin
      button-text: Sign In
      ```

      Don't have an account? [Sign up](/signup)
    MARKDOWN

    File.write(File.join(pages_path, 'signin.md'), signin_content)
    puts "✓ Generated members/signin.md page"
  end

  def generate_check_email_page(pages_path)
    return if File.exist?(File.join(pages_path, 'check-email.md'))

    check_email_content = <<~MARKDOWN
      ---
      title: Check Your Email
      url_name: check-email
      status: published
      audience: everyone
      ---

      # Check Your Email

      We've sent you a magic link to sign in.

      **Check your inbox** and click the link to continue.

      The link will sign you in automatically.

      ---

      Didn't receive it? [Try again](/signin)
    MARKDOWN

    File.write(File.join(pages_path, 'check-email.md'), check_email_content)
    puts "✓ Generated members/check-email.md page"
  end

  def generate_upgrade_page(pages_path)
    return if File.exist?(File.join(pages_path, 'upgrade.md'))

    upgrade_content = <<~MARKDOWN
      ---
      title: Upgrade
      url_name: upgrade
      status: published
      audience: everyone
      ---

      # Unlock Premium Content

      This is a one-time payment, no subscription required, access forever[^1].

      ## What You Get

      - Full access to premium articles
      - Exclusive member-only podcast episodes
      - An ebook of your choice
      - Support independent publishing

      ## Ready to Upgrade?

      ```form
      for: checkout
      member-button-text: Upgrade Now
      non-member-button-text: Sign up as paid member
      ```

      Secure payment powered by Stripe. You'll receive your login password after payment.

      [^1]: As long as this site is around (and perhaps even longer).
    MARKDOWN

    File.write(File.join(pages_path, 'upgrade.md'), upgrade_content)
    puts "✓ Generated members/upgrade.md page"
  end

  def generate_donate_page(pages_path)
    return if File.exist?(File.join(pages_path, 'donate.md'))

    donate_content = <<~MARKDOWN
      ---
      title: Support this site
      url_name: donate
      status: published
      audience: everyone
      ---

      # Support this site

      If this work has been useful to you and you'd like to help keep it going, you can chip in any amount. One-time payment, no subscription, no account required.

      ```form
      for: donate
      button-text: Continue to Stripe →
      ```

      Secure payment powered by Stripe.
    MARKDOWN

    File.write(File.join(pages_path, 'donate.md'), donate_content)
    puts "✓ Generated members/donate.md page"
  end

  def generate_unsubscribe_page(pages_path)
    return if File.exist?(File.join(pages_path, 'unsubscribe.md'))

    unsubscribe_content = <<~MARKDOWN
      ---
      title: Unsubscribe from Newsletter
      url_name: unsubscribe
      status: published
      audience: everyone
      ---

      # Unsubscribe from Newsletter

      Are you sure you want to unsubscribe from our newsletter?

      You'll no longer receive new posts and updates via email.

      ```form
      for: unsubscribe
      button-text: Yes, Unsubscribe
      ```

      [Go back home](/)
    MARKDOWN

    File.write(File.join(pages_path, 'unsubscribe.md'), unsubscribe_content)
    puts "✓ Generated members/unsubscribe.md page"
  end

  def generate_unsubscribed_page(pages_path)
    return if File.exist?(File.join(pages_path, 'unsubscribed.md'))

    unsubscribed_content = <<~MARKDOWN
      ---
      title: You've Been Unsubscribed
      url_name: unsubscribed
      status: published
      audience: everyone
      ---

      # ✓ You've been unsubscribed

      You've been removed from our newsletter.

      You won't receive any more emails from us.

      ## Changed your mind?

      You can resubscribe anytime in your [account settings](/account).

      [Return home](/)
    MARKDOWN

    File.write(File.join(pages_path, 'unsubscribed.md'), unsubscribed_content)
    puts "✓ Generated members/unsubscribed.md page"
  end

  def generate_member_emails
    emails_path = File.join(RoeSitePaths::SITE_PATH, 'emails')
    FileUtils.mkdir_p(emails_path)

    # Magic link email
    unless File.exist?(File.join(emails_path, 'magic_link.md'))
      magic_link_content = <<~MARKDOWN
        # Sign in to @site_name

        Hi @member_name,

        Click the link below to sign in:

        [@magic_link](@magic_link)

        ---

        This link will sign you in automatically and expires in 24 hours.

        If you didn't request this, you can safely ignore this email.
      MARKDOWN

      File.write(File.join(emails_path, 'magic_link.md'), magic_link_content)
      puts "✓ Generated magic_link.md email template"
    end

    # Welcome email
    unless File.exist?(File.join(emails_path, 'welcome.md'))
      welcome_content = <<~MARKDOWN
        # Welcome to @site_name!

        Hi @member_name,

        Thanks for joining @site_name. We're excited to have you here!

        ---

        If you have any questions, just reply to this email.
      MARKDOWN

      File.write(File.join(emails_path, 'welcome.md'), welcome_content)
      puts "✓ Generated welcome.md email template"
    end

    # Upgrade success email
    unless File.exist?(File.join(emails_path, 'upgrade_success.md'))
      upgrade_success_content = <<~MARKDOWN
        # Your membership is active!

        Hi @member_name,

        Your paid membership to @site_name is now active. Thank you for your support!

        **Your password:** `@password`

        You can manage your account at any time: [@account_url](@account_url)

        ---

        If you have any questions, just reply to this email.
      MARKDOWN

      File.write(File.join(emails_path, 'upgrade_success.md'), upgrade_success_content)
      puts "✓ Generated upgrade_success.md email template"
    end

    # Email changed email
    unless File.exist?(File.join(emails_path, 'email_changed.md'))
      email_changed_content = <<~MARKDOWN
        # Your email has been changed

        Hi @member_name,

        This confirms that your email address has been changed from **@old_email** to **@new_email**.

        If you didn't make this change, please contact us immediately.

        ---

        @site_name
      MARKDOWN

      File.write(File.join(emails_path, 'email_changed.md'), email_changed_content)
      puts "✓ Generated email_changed.md email template"
    end

    # Membership cancelled email
    unless File.exist?(File.join(emails_path, 'membership_cancelled.md'))
      membership_cancelled_content = <<~MARKDOWN
        # Your membership has been cancelled

        Hi @member_name,

        This confirms that your paid membership to @site_name has been cancelled.

        You'll continue to have access until the end of your billing period, then you'll be switched to free access.

        You're welcome to upgrade again at any time.

        ---

        @site_name
      MARKDOWN

      File.write(File.join(emails_path, 'membership_cancelled.md'), membership_cancelled_content)
      puts "✓ Generated membership_cancelled.md email template"
    end

    # Email confirmation email
    unless File.exist?(File.join(emails_path, 'email_confirmation.md'))
      email_confirmation_content = <<~MARKDOWN
        # Confirm your email address

        Hi @member_name,

        You changed your email address. Click the link below to confirm your new email:

        [@confirmation_link](@confirmation_link)

        ---

        This link expires in 24 hours.

        If you didn't request this change, you can safely ignore this email and your email address will remain unchanged.
      MARKDOWN

      File.write(File.join(emails_path, 'email_confirmation.md'), email_confirmation_content)
      puts "✓ Generated email_confirmation.md email template"
    end

    # Payment failed email
    unless File.exist?(File.join(emails_path, 'payment_failed.md'))
      payment_failed_content = <<~MARKDOWN
        # Payment Update Required

        Hi @member_name,

        We weren't able to process your payment for @site_name.

        Your free access will continue, but please update your payment method to keep your paid membership:

        [Update Payment Method](@update_payment_url)

        ---

        Questions? Just reply to this email.
      MARKDOWN

      File.write(File.join(emails_path, 'payment_failed.md'), payment_failed_content)
      puts "✓ Generated payment_failed.md email template"
    end

    # Account deletion email
    unless File.exist?(File.join(emails_path, 'account_deletion.md'))
      account_deletion_content = <<~MARKDOWN
        # Your account has been deleted

        Hi @member_name,

        This confirms that your account at @site_name has been permanently deleted.

        All of your data has been removed from our system.

        We're sorry to see you go. If you'd like to return in the future, you're always welcome to sign up again.

        ---

        @site_name
      MARKDOWN

      File.write(File.join(emails_path, 'account_deletion.md'), account_deletion_content)
      puts "✓ Generated account_deletion.md email template"
    end
  end

  private

  def ensure_directories
    FileUtils.mkdir_p(INTEGRATIONS_PATH)
    FileUtils.mkdir_p(SYSTEM_PATH)
    FileUtils.mkdir_p(SITE_PATH)
    FileUtils.mkdir_p(FEATURES_PATH)
    FileUtils.mkdir_p(DEFAULTS_PATH)
    FileUtils.mkdir_p(File.join(ASSETS_PATH, 'fonts'))
    FileUtils.mkdir_p(File.join(ASSETS_PATH, 'images'))

    # Copy default 404 image if it doesn't exist
    copy_default_404_image
  end

  def copy_default_404_image
    source = Rails.root.join('app', 'assets', 'images', '404.png')
    dest = File.join(ASSETS_PATH, 'images', '404.png')

    # Only copy if source exists and dest doesn't
    if File.exist?(source) && !File.exist?(dest)
      FileUtils.cp(source, dest)
      puts "  ✓ Copied default 404.png to system assets"
    end
  end

  def generate_site_config
    content = <<~YAML
      title: ""
      description: ""
      author: ""
      author_email: ""
      logo: ""
      logo_style: ""
      favicon: ""
      theme:
        active: "default"
      static_generation_enabled: false
    YAML

    File.write(File.join(SITE_PATH, 'site.yml'), content)
    puts "✓ Generated site/site.yml"
  end

  def generate_fonts_config
    content = <<~YAML
      heading:
        family: "Manrope"
        source: "google"
      body:
        family: "Source Serif 4"
        source: "google"
      mono:
        family: "Inconsolata"
        source: "google"
      accent:
        family: ""
        source: ""
    YAML

    File.write(File.join(SITE_PATH, 'fonts.yml'), content)
    puts "✓ Generated site/fonts.yml"
  end

  def generate_cards_defaults
    content = <<~YAML
      post-link:
        default_image: /media/images/default-post.jpg
        default_style: small
        default_link_text: "Read full story →"
      aside:
        default_link_text: "→"
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

    File.write(File.join(DEFAULTS_PATH, 'cards.yml'), content)
    puts "✓ Generated defaults/cards.yml"
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

    File.write(File.join(DEFAULTS_PATH, 'collections.yml'), content)
    puts "✓ Generated defaults/collections.yml"
  end

  def generate_welcome_post
    posts_path = File.join(RoeSitePaths::SITE_PATH, 'posts')
    welcome_file = File.join(posts_path, 'welcome.md')

    return if File.exist?(welcome_file)
    return if Dir.exist?(posts_path) && Dir.glob(File.join(posts_path, '*.md')).any?

    FileUtils.mkdir_p(posts_path)

    content = <<~MARKDOWN
      ---
      title: Welcome to Roe
      description: Your file-backed CMS is ready to go
      date: #{Date.today}
      status: published
      type: article
      ---

      # Welcome to Roe! 🚀

      Your new site is up and running. Roe is a file-backed CMS that keeps your content in plain Markdown files — easy to edit, version control, and deploy anywhere.

      ## Quick Start

      1. **Configure your site**: Visit the [admin panel](/admin) to set your site title, URL, and other settings
      2. **Create content**: Add posts to the `site/posts/` folder as Markdown files
      3. **Customize the theme**: Edit files in `site/layout/` and `site/theme/`
      4. **Deploy**: Use the Updates & Deploy page to push your site live

      ## Content Structure

      - **Posts** → `site/posts/*.md` — Blog posts, articles, podcasts
      - **Pages** → `site/pages/*.md` — Static pages like About, Contact
      - **Media** → `site/media/` — Images, audio, video files
      - **Config** → `site/system/` — Site settings and feature flags

      ## Need Help?

      - Check the documentation in `current/docs/`
      - Visit the Admin panel for content management
      - Look at this post's source: `site/posts/welcome.md`

      Happy publishing! ✍️
    MARKDOWN

    File.write(welcome_file, content)
    puts "✓ Generated welcome post at posts/welcome.md"
  end
end
