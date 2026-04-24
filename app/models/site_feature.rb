# Centralized feature-flag predicates. Used by both views (via
# ApplicationHelper, which delegates here) and models. Keeping the logic
# in one place avoids drift and lets things like Post#needs_attention?
# check the same gates the publish modal does without pulling in the
# whole helper context.
module SiteFeature
  module_function

  def members_enabled?
    File.exist?(Rails.root.join('site/system/features/members.yml'))
  end

  def payments_enabled?
    members_enabled? && SiteConfig.feature('members', 'payments.enabled') == true
  end

  def newsletters_enabled?
    members_enabled? && SiteConfig.feature('members', 'newsletter.enabled') == true
  end

  def store_enabled?
    File.exist?(Rails.root.join('site/system/features/store.yml'))
  end

  def postmark_configured?
    PostmarkConfig.exists? && PostmarkConfig.current.connected?
  end
end
