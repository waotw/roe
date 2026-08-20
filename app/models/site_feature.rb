# Centralized feature-flag predicates. Used by both views (via
# ApplicationHelper, which delegates here) and models.
#
# Two distinct concepts:
#   enabled?   — feature file exists (user turned it on)
#   configured? — integration file has keys AND last API verification succeeded
#
# Orange dot / [unconfigured] tag logic:
#   Show when: feature enabled + current mode's key absent OR not yet verified
#   Hide when: successful API verification for current active mode
#   Return when: current mode's key is cleared
module SiteFeature
  module_function

  INTEGRATIONS_PATH = File.join(RoeSitePaths::SITE_PATH, "system", "integrations")
  FEATURES_PATH     = File.join(RoeSitePaths::SITE_PATH, "system", "features")

  # ── Feature enabled (file presence) ────────────────────────────────────

  def members_enabled?
    File.exist?(File.join(FEATURES_PATH, "members.yml"))
  end

  def store_enabled?
    File.exist?(File.join(FEATURES_PATH, "store.yml"))
  end

  def podcast_enabled?
    File.exist?(File.join(FEATURES_PATH, "podcast.yml"))
  end

  def custom_feeds_enabled?
    File.exist?(File.join(FEATURES_PATH, "feeds.yml"))
  end

  def music_enabled?
    File.exist?(File.join(FEATURES_PATH, "music.yml"))
  end

  # Payments enabled = members enabled AND payments.enabled in members.yml
  def payments_feature_enabled?
    return false unless members_enabled?
    SiteConfig.feature("members", "payments.enabled") == true
  end

  # Email is required by members, not optional alongside them: a magic link IS
  # the sign-in mechanism, so a members site with no way to send one has no way
  # to let anyone in. Enabled with members, never separately.
  #
  # This used to hang off newsletter.enabled, which meant a site running free
  # members with newsletters off never had postmark.yml generated and never saw
  # the setting in Settings — so every sign-in email fell through to a fallback
  # mailer that reports success and delivers nothing.
  def email_feature_enabled?
    members_enabled?
  end

  # Newsletters enabled = members enabled AND newsletter.enabled in members.yml.
  # Sending posts as broadcasts, and nothing else — it no longer decides whether
  # email works at all.
  def newsletters_feature_enabled?
    return false unless members_enabled?
    SiteConfig.feature("members", "newsletter.enabled") == true
  end

  # ── Integration files present ───────────────────────────────────────────

  def payments_integration_file?
    File.exist?(File.join(INTEGRATIONS_PATH, "stripe.yml"))
  end

  def email_integration_file?
    File.exist?(File.join(INTEGRATIONS_PATH, "postmark.yml"))
  end
  alias_method :newsletters_integration_file?, :email_integration_file?

  def snipcart_integration_file?
    File.exist?(File.join(INTEGRATIONS_PATH, "snipcart.yml"))
  end

  # ── Keys present (integration file has keys) ────────────────────────────

  def payments_enabled?
    payments_feature_enabled? && StripeConfig.current.keys_present?
  end

  # Can we actually send anything: the feature is on and Postmark has keys.
  def email_enabled?
    email_feature_enabled? && PostmarkConfig.current.keys_present?
  end

  # Can we send a newsletter: email works AND broadcasts are turned on.
  def newsletters_enabled?
    newsletters_feature_enabled? && PostmarkConfig.current.keys_present?
  end

  # ── Integration configured (keys + verified) ────────────────────────────

  def stripe_configured?
    StripeConfig.current.connected?
  end

  def postmark_configured?
    PostmarkConfig.current.connected?
  end

  def snipcart_configured?
    SnipcartConfig.current.connected?
  end

  # ── Orange dot / [unconfigured] tag ─────────────────────────────────────
  # Returns true if ANY enabled integration needs attention for current mode.

  def any_integration_unconfigured?
    payments_unconfigured? || email_unconfigured? || snipcart_unconfigured?
  end

  def payments_unconfigured?
    payments_feature_enabled? && !stripe_configured?
  end

  # The orange dot follows members, not newsletters. A members site without
  # working email is broken whether or not it ever sends a broadcast.
  def email_unconfigured?
    email_feature_enabled? && !postmark_configured?
  end
  alias_method :newsletters_unconfigured?, :email_unconfigured?

  def snipcart_unconfigured?
    store_enabled? && !snipcart_configured?
  end

  # ── Payments mode / memberships / donations ─────────────────────────────

  def payments_mode
    return nil unless payments_feature_enabled?
    SiteConfig.feature("members", "payments.mode").presence || "memberships"
  end

  def memberships_enabled?
    payments_enabled? && payments_mode.in?(%w[memberships both])
  end

  def donations_enabled?
    payments_enabled? && payments_mode.in?(%w[donations both])
  end

  def donation_amounts
    raw = SiteConfig.feature("members", "payments.donation_amounts")

    parsed = case raw
    when Array
               raw
    when String
               raw.delete("[]").split(",").map(&:strip).reject(&:empty?)
    else
               []
    end

    nums = parsed.map { |v| Integer(v.to_s, exception: false) || Float(v.to_s, exception: false) }.compact
    nums.presence || [ 5, 10, 20, 50 ]
  end

  # ── Legacy / convenience ─────────────────────────────────────────────────

  def integrations_to_enable?
    !members_enabled? || !store_enabled?
  end
end
