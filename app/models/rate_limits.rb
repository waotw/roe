# frozen_string_literal: true

# Rate limits for the public, unauthenticated endpoints, read from
# security.yml so a site owner can loosen or tighten them without a deploy.
#
# WHAT THIS IS NOT: protection against a denial-of-service attack. By the time
# a request reaches Rails the bandwidth, the handshake and a Puma thread are
# already spent. A flood is stopped at the edge or not at all. This is here to
# make abuse of expensive endpoints — sending email, creating accounts, guessing
# tokens — cost more than it's worth.
#
# THE RULE THAT SHAPES ALL OF THIS: a limit must never lock out someone who
# belongs here. Two decisions follow from it.
#
# Key on the narrowest thing that identifies the abuse, which usually isn't the
# IP address. Behind carrier-grade NAT a whole mobile network shares one; so
# does an office, a university, a VPN. An IP limit on sign-in is how a paying
# member ends up locked out of a service because of who else is on their
# network. Flooding one person's inbox is abuse of that address, so the magic
# link is counted per address and a shared IP is nobody's problem.
#
# And prefer withholding the expensive part to refusing the request. Hitting the
# magic-link limit doesn't block signing in — it stops sending another email and
# says one is already on its way, which is both true and what the person needed
# to hear. Nobody is turned away.
class RateLimits
  # Generous on purpose. These are the numbers a real person would have to work
  # to exceed, not the smallest ones that would still technically function.
  #
  #   to:     requests allowed in the window
  #   within: window length, in minutes
  #   by:     what the count is keyed on — :email, or :ip where there's nothing
  #           narrower to use
  DEFAULTS = {
    "magic_link" => { "to" => 5,  "within" => 15, "by" => :email },
    "signup"     => { "to" => 20, "within" => 60, "by" => :ip },
    "checkout"   => { "to" => 20, "within" => 60, "by" => :ip },
    "token"      => { "to" => 30, "within" => 60, "by" => :ip }
  }.freeze

  # Deliberately absent: the search index. It's one URL holding the public
  # corpus, so a scraper needs exactly one request — the same request a reader
  # makes when they open search. There's no number that tells those apart, and
  # the index carries less than the pages it points at (2,000 characters an
  # item, code and images stripped), so nothing is being withheld by guarding
  # it. robots.txt keeps it out of crawlers that honour robots.txt; that's the
  # honest limit of what can be done here.

  # Ceilings, not suggestions. A typo of 0 in the config would lock every reader
  # out of signing in, which is the exact failure this is meant to avoid, so a
  # value below 1 is read as "not configured" rather than "allow nothing".
  MIN_TO = 1
  MIN_WITHIN = 1

  class << self
    def enabled?
      value = config["enabled"]
      value.nil? ? true : value.to_s.strip.casecmp("true").zero?
    end

    # { to:, within:, by: } for a limit, falling back to the default for
    # anything the config doesn't set or sets nonsensically.
    def for(name)
      key = name.to_s
      default = DEFAULTS.fetch(key)
      set = config.dig("limits", key) || {}

      {
        to: positive_int(set["to"], default["to"], MIN_TO),
        within: positive_int(set["within"], default["within"], MIN_WITHIN).minutes,
        by: default["by"]
      }
    end

    def names = DEFAULTS.keys

    private

    def config
      SiteConfig.current("security")&.config || {}
    rescue StandardError => e
      # A missing or unreadable security.yml means the defaults apply, never
      # that the site stops working.
      Rails.logger.warn "[RateLimits] falling back to defaults: #{e.class} #{e.message}"
      {}
    end

    def positive_int(value, fallback, minimum)
      number = Integer(value.to_s, exception: false)
      number && number >= minimum ? number : fallback
    end
  end
end
