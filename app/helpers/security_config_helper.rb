# frozen_string_literal: true

# Values for the security.yml form.
module SecurityConfigHelper
  # What a field shows when security.yml doesn't set it. Blank would be a lie:
  # a site with no file is still rate limited, on RateLimits::DEFAULTS. The form
  # reports what's actually running.
  def security_field_value(flattened_config, field_name)
    set = flattened_config[field_name]
    return set unless set.nil? || set.to_s.strip.empty?

    return RateLimits.enabled? if field_name == "enabled"
    return AiCrawlers.mode if field_name == "ai_crawlers"

    _, name, key = field_name.split(".")
    RateLimits::DEFAULTS.dig(name, key)
  end
end
