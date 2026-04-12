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

  def generate_members_defaults(show_paid_content: true, payments_enabled: false, payment_price: "0.00", newsletter_enabled: false)
    # Generate members.yml
    content = <<~YAML
      payments:
        enabled: #{payments_enabled}
        price: "#{payment_price}"
      newsletter:
        enabled: #{newsletter_enabled}
      everyone:
        show_paid_content: #{show_paid_content}
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

    # Generate email templates
    generate_member_emails
  end

  def generate_member_pages
    pages_path = Rails.root.join('site', 'pages', 'members')
    FileUtils.mkdir_p(pages_path)

    # Generate all member pages
    generate_signup_page(pages_path)
    generate_signin_page(pages_path)
    generate_check_email_page(pages_path)
    generate_upgrade_page(pages_path)
    generate_unsubscribe_page(pages_path)
    generate_unsubscribed_page(pages_path)

    # Generate email templates
    generate_member_emails
  end

  def generate_signup_page(pages_path)
    return if File.exist?(pages_path.join('signup.md'))

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

    File.write(pages_path.join('signup.md'), signup_content)
    puts "✓ Generated members/signup.md page"
  end

  def generate_signin_page(pages_path)
    return if File.exist?(pages_path.join('signin.md'))

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

    File.write(pages_path.join('signin.md'), signin_content)
    puts "✓ Generated members/signin.md page"
  end

  def generate_check_email_page(pages_path)
    return if File.exist?(pages_path.join('check-email.md'))

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

    File.write(pages_path.join('check-email.md'), check_email_content)
    puts "✓ Generated members/check-email.md page"
  end

  def generate_upgrade_page(pages_path)
    return if File.exist?(pages_path.join('upgrade.md'))

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

    File.write(pages_path.join('upgrade.md'), upgrade_content)
    puts "✓ Generated members/upgrade.md page"
  end

  def generate_unsubscribe_page(pages_path)
    return if File.exist?(pages_path.join('unsubscribe.md'))

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

    File.write(pages_path.join('unsubscribe.md'), unsubscribe_content)
    puts "✓ Generated members/unsubscribe.md page"
  end

  def generate_unsubscribed_page(pages_path)
    return if File.exist?(pages_path.join('unsubscribed.md'))

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

    File.write(pages_path.join('unsubscribed.md'), unsubscribed_content)
    puts "✓ Generated members/unsubscribed.md page"
  end

  def generate_member_emails
    emails_path = Rails.root.join('site', 'emails')
    FileUtils.mkdir_p(emails_path)

    # Magic link email
    unless File.exist?(emails_path.join('magic_link.md'))
      magic_link_content = <<~MARKDOWN
        # Sign in to @site_name

        Hi @member_name,

        Click the link below to sign in:

        [@magic_link](@magic_link)

        ---

        This link will sign you in automatically and expires in 24 hours.

        If you didn't request this, you can safely ignore this email.
      MARKDOWN

      File.write(emails_path.join('magic_link.md'), magic_link_content)
      puts "✓ Generated magic_link.md email template"
    end

    # Welcome email
    unless File.exist?(emails_path.join('welcome.md'))
      welcome_content = <<~MARKDOWN
        # Welcome to @site_name!

        Hi @member_name,

        Thanks for joining @site_name. We're excited to have you here!

        ---

        If you have any questions, just reply to this email.
      MARKDOWN

      File.write(emails_path.join('welcome.md'), welcome_content)
      puts "✓ Generated welcome.md email template"
    end

    # Upgrade success email
    unless File.exist?(emails_path.join('upgrade_success.md'))
      upgrade_success_content = <<~MARKDOWN
        # Your membership is active!

        Hi @member_name,

        Your paid membership to @site_name is now active. Thank you for your support!

        **Your password:** `@password`

        You can manage your account at any time: [@account_url](@account_url)

        ---

        If you have any questions, just reply to this email.
      MARKDOWN

      File.write(emails_path.join('upgrade_success.md'), upgrade_success_content)
      puts "✓ Generated upgrade_success.md email template"
    end

    # Email changed email
    unless File.exist?(emails_path.join('email_changed.md'))
      email_changed_content = <<~MARKDOWN
        # Your email has been changed

        Hi @member_name,

        This confirms that your email address has been changed from **@old_email** to **@new_email**.

        If you didn't make this change, please contact us immediately.

        ---

        @site_name
      MARKDOWN

      File.write(emails_path.join('email_changed.md'), email_changed_content)
      puts "✓ Generated email_changed.md email template"
    end

    # Membership cancelled email
    unless File.exist?(emails_path.join('membership_cancelled.md'))
      membership_cancelled_content = <<~MARKDOWN
        # Your membership has been cancelled

        Hi @member_name,

        This confirms that your paid membership to @site_name has been cancelled.

        You'll continue to have access until the end of your billing period, then you'll be switched to free access.

        You're welcome to upgrade again at any time.

        ---

        @site_name
      MARKDOWN

      File.write(emails_path.join('membership_cancelled.md'), membership_cancelled_content)
      puts "✓ Generated membership_cancelled.md email template"
    end

    # Email confirmation email
    unless File.exist?(emails_path.join('email_confirmation.md'))
      email_confirmation_content = <<~MARKDOWN
        # Confirm your email address

        Hi @member_name,

        You changed your email address. Click the link below to confirm your new email:

        [@confirmation_link](@confirmation_link)

        ---

        This link expires in 24 hours.

        If you didn't request this change, you can safely ignore this email and your email address will remain unchanged.
      MARKDOWN

      File.write(emails_path.join('email_confirmation.md'), email_confirmation_content)
      puts "✓ Generated email_confirmation.md email template"
    end

    # Payment failed email
    unless File.exist?(emails_path.join('payment_failed.md'))
      payment_failed_content = <<~MARKDOWN
        # Payment Update Required

        Hi @member_name,

        We weren't able to process your payment for @site_name.

        Your free access will continue, but please update your payment method to keep your paid membership:

        [Update Payment Method](@update_payment_url)

        ---

        Questions? Just reply to this email.
      MARKDOWN

      File.write(emails_path.join('payment_failed.md'), payment_failed_content)
      puts "✓ Generated payment_failed.md email template"
    end

    # Account deletion email
    unless File.exist?(emails_path.join('account_deletion.md'))
      account_deletion_content = <<~MARKDOWN
        # Your account has been deleted

        Hi @member_name,

        This confirms that your account at @site_name has been permanently deleted.

        All of your data has been removed from our system.

        We're sorry to see you go. If you'd like to return in the future, you're always welcome to sign up again.

        ---

        @site_name
      MARKDOWN

      File.write(emails_path.join('account_deletion.md'), account_deletion_content)
      puts "✓ Generated account_deletion.md email template"
    end
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
