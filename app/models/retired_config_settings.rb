# Settings a Roe update stopped reading, and what replaced them.
#
# Roe never rewrites a file under site/ on update — those files are the user's,
# they aren't in git, and Site Sync propagates whatever's there. So a setting
# that moves leaves the old key behind. This class is what lets the admin say
# "this key does nothing now, here's what took over, click to remove it."
#
# The rule that keeps this safe: a retired setting is never load-bearing by the
# time it gets here. Whatever replaced it already has a value, so the page works
# whether or not the user ever clicks Cleanup. This is tidying, not repair.
#
# Right now there's one migration, so it's written plainly rather than as a
# manifest. When there's a second, the shape to extract is: which file, which
# keys, what they map to, and the sentence explaining why.
class RetiredConfigSettings
  # Button templates were a block of YAML-ish text an editor button pasted into
  # the document. The card and collection builders replaced that path, leaving
  # the templates as an invisible second copy of settings the config already
  # had — and in collections.yml the two had drifted apart (`limit: 5` in the
  # template, `default_limit: 10` in the settings).
  #
  # A template line `limit: 5` corresponds to the setting `default_limit`. That
  # one rule covers both files.
  TEMPLATE_KEY_SUFFIX = "button_template"

  # Which card type a cards.yml template key belonged to.
  CARD_TYPES = {
    "pullquote_button_template"    => "pullquote",
    "aside_button_template"        => "aside",
    "post_link_button_template"    => "post-link",
    "product_link_button_template" => "product-link"
  }.freeze

  def self.retired_key?(key)
    key.to_s == TEMPLATE_KEY_SUFFIX || key.to_s.end_with?("_#{TEMPLATE_KEY_SUFFIX}")
  end

  # The dead keys present in a parsed config file.
  def self.in_config(config)
    return {} unless config.is_a?(Hash)
    config.select { |k, _| retired_key?(k) }
  end

  # One row per setting the old template actually carried, for the admin table.
  # A line whose value is the placeholder token, or which names something the
  # builder doesn't have a field for, is skipped — it was never a setting.
  def self.replacements_for(config_type, template_key, template_text)
    parse(template_text).filter_map do |field, value|
      setting = "default_#{field}"
      current = current_setting(config_type, template_key, setting)
      next if current.nil?

      { from: field, value: value, to: setting,
        current: current.to_s, differs: current.to_s.strip != value.to_s.strip }
    end
  end

  # `key: value` lines, minus the placeholder and minus `type:` (which named the
  # card, and is chosen from the builder's dropdown now).
  def self.parse(template_text)
    template_text.to_s.each_line.filter_map do |line|
      key, value = line.split(":", 2).map { |s| s.to_s.strip }
      next if key.blank? || value.blank?
      next if key == "type" || value == "__PLACEHOLDER__"
      [ key, value ]
    end
  end

  # nil when the replacement setting doesn't exist for this file — which means
  # the old line had no equivalent and there's nothing to show the user.
  def self.current_setting(config_type, template_key, setting)
    case config_type.to_s
    when "collections"
      value = SiteConfig.default("collections", setting)
      value.nil? ? nil : value
    when "cards"
      card_type = CARD_TYPES[template_key.to_s] or return nil
      settings = SiteConfig.default("cards", card_type)
      return nil unless settings.is_a?(Hash) && settings.key?(setting)
      settings[setting]
    end
  end

  # Strip the retired keys from a config file, leaving everything else as it is.
  # Returns the keys removed.
  def self.strip!(path)
    return [] unless File.exist?(path)

    config = YAML.safe_load(File.read(path), permitted_classes: [ Date, Time ])
    return [] unless config.is_a?(Hash)

    removed = in_config(config).keys
    return [] if removed.empty?

    config = config.reject { |k, _| retired_key?(k) }
    File.write(path, config.to_yaml.sub(/\A---\s*\n/, ""))
    removed
  end
end
