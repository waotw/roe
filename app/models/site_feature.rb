# Centralized feature-flag predicates. Used by both views (via
# ApplicationHelper, which delegates here) and models. Keeping the logic
# in one place avoids drift and lets things like Post#needs_attention?
# check the same gates the publish modal does without pulling in the
# whole helper context.
module SiteFeature
  module_function

  def members_enabled?
    File.exist?(File.join(RoeSitePaths::SITE_PATH, 'system/features/members.yml'))
  end

  def payments_enabled?
    members_enabled? && SiteConfig.feature('members', 'payments.enabled') == true
  end

  # When payments is on, the writer picks one of three modes:
  # memberships, donations, or both. Old configs without a mode default
  # to memberships (the original behavior, preserved for back-compat).
  def payments_mode
    return nil unless payments_enabled?
    SiteConfig.feature('members', 'payments.mode').presence || 'memberships'
  end

  def memberships_enabled?
    payments_enabled? && payments_mode.in?(%w[memberships both])
  end

  def donations_enabled?
    payments_enabled? && payments_mode.in?(%w[donations both])
  end

  # Donation preset amounts (whole dollars). Falls back to a sensible
  # default if the writer hasn't customized them.
  #
  # Defensive parsing: the config editor sometimes stores the value as
  # a literal string like `"[5, 10, 20, 50]"` instead of a true YAML
  # array. We accept both shapes so the form doesn't render one button
  # containing the array text.
  def donation_amounts
    raw = SiteConfig.feature('members', 'payments.donation_amounts')

    parsed = case raw
             when Array
               raw
             when String
               # Strip brackets and split on commas, tolerating whitespace.
               raw.delete("[]").split(",").map(&:strip).reject(&:empty?)
             else
               []
             end

    nums = parsed.map { |v| Integer(v.to_s, exception: false) || Float(v.to_s, exception: false) }.compact
    nums.presence || [5, 10, 20, 50]
  end

  def newsletters_enabled?
    members_enabled? && SiteConfig.feature('members', "newsletter & email.enabled") == true
  end

  def store_enabled?
    File.exist?(File.join(RoeSitePaths::SITE_PATH, 'system/features/store.yml'))
  end

  def postmark_configured?
    PostmarkConfig.exists? && PostmarkConfig.current.connected?
  end

  # Framework-dev override: lets the Roe maintainer work on production-only
  # features (members, store, integrations) from a development environment,
  # and on dev-only features (Substack importer) from production. End users
  # never set this — it's gated behind a non-obvious env var name and
  # specific value so casual inspection of `Rails.env` checks won't reveal
  # the seam.
  #
  # Why: the dev/prod feature split intentionally hides production-only
  # surfaces in dev (and vice versa) so site owners aren't tempted to
  # configure things in the wrong place. The maintainer still needs to
  # build and test those surfaces, hence this escape hatch.
  def framework_dev_mode?
    ENV['ROE_DEV_OVERRIDE'] == 'on'
  end

  # Show production-only features (members, store, integrations) when:
  #   - we're actually in production, OR
  #   - the framework-dev override is on (maintainer working in dev)
  def show_production_features?
    Rails.env.production? || framework_dev_mode?
  end

  # Show development-only features (Substack importer, Tools menu) when:
  #   - we're actually in development, OR
  #   - the framework-dev override is on (maintainer testing on prod)
  def show_development_features?
    Rails.env.development? || framework_dev_mode?
  end
end
