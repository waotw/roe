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
    # Generate members.yml
    content = <<~YAML
      non-members:
        show_paid_content: #{show_paid_content}
        show_paid_indicator: true

      payments:
        enabled: false
        price: "0.00"

      members:
    YAML

    File.write(DEFAULTS_PATH.join('members.yml'), content)
    puts "✓ Generated members.yml"

    # Generate member pages
    generate_member_pages
  end

  def generate_member_pages
    pages_path = Rails.root.join('site', 'pages')
    FileUtils.mkdir_p(pages_path)

    # Generate signup page
    generate_signup_page(pages_path)

    # Generate signin page
    generate_signin_page(pages_path)

    # Generate check email confirmation page
    generate_check_email_page(pages_path)

    # Generate upgrade page
    generate_upgrade_page
  end

  def generate_upgrade_page
    pages_path = Rails.root.join('site', 'pages')
    FileUtils.mkdir_p(pages_path)

    upgrade_content = <<~MARKDOWN
      ---
      title: Upgrade
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

    File.write(pages_path.join('upgrade.md'), upgrade_content)
    puts "✓ Generated upgrade.md page"
  end

  def generate_signup_page(pages_path)
    signup_content = <<~MARKDOWN
      ---
      title: Sign Up
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

      Already have an account? [Sign in](/sign-in)


      [^1]: I will never sell your data either.
    MARKDOWN

    File.write(pages_path.join('signup.md'), signup_content)
    puts "✓ Generated signup.md page"
  end

  def generate_signin_page(pages_path)
    signin_content = <<~MARKDOWN
      ---
      title: Sign In
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

      Don't have an account? [Sign up](/sign-up)
    MARKDOWN

    File.write(pages_path.join('signin.md'), signin_content)
    puts "✓ Generated signin.md page"
  end

  def generate_check_email_page(pages_path)
    check_email_content = <<~MARKDOWN
      ---
      title: Check Your Email
      status: published
      audience: everyone
      ---

      # Check Your Email

      We've sent you a magic link to sign in.

      **Check your inbox** and click the link to continue.

      The link will sign you in automatically.

      ---

      Didn't receive it? [Try again](/sign-in)
    MARKDOWN

    File.write(pages_path.join('check-email.md'), check_email_content)
    puts "✓ Generated check-email.md page"
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
      fonts:
        heading:
          family: "Manrope"
          source: "google"
        body:
          family: "Source Serif 4"
          source: "google"
        mono:
          family: "Inconsolata"
          source: "google"
    YAML

    File.write(SYSTEM_PATH.join('site.yml'), content)
    puts "✓ Generated site.yml"
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
