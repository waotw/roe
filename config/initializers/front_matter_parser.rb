require "psych"

# Monkey-patch Psych to allow Date, Time, Symbol globally for this app
module Psych
  class << self
    alias_method :original_safe_load, :safe_load

    def safe_load(yaml, **kwargs)
      kwargs[:permitted_classes] ||= []
      kwargs[:permitted_classes] += [ Date, Time, Symbol ]
      kwargs[:aliases] = true unless kwargs.key?(:aliases)
      original_safe_load(yaml, **kwargs)
    end
  end
end
