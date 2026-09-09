# frozen_string_literal: true

# Rate limiting for the public endpoints, with the limits read at request time.
#
# Rails 8 ships `rate_limit`, and the admin-side controllers use it. It bakes
# `to:` and `within:` in when the class loads, which is right for a constant and
# wrong for a setting someone edits in an admin panel — the change wouldn't take
# until the server restarted. Every other Roe config takes effect on save, so
# this mirrors Rails' implementation (increment a counter, compare, act) while
# reading RateLimits per request.
#
#   limit_requests :magic_link, only: :create, with: -> { ... }
#
# FAILS OPEN. If the cache store is unavailable the request is allowed through.
# A rate limiter that locks people out when its own backend is having a bad day
# is worse than no rate limiter.
module RateLimited
  extend ActiveSupport::Concern

  class_methods do
    def limit_requests(name, with:, **options)
      before_action(**options) { enforce_rate_limit(name, with) }
    end
  end

  private

  def enforce_rate_limit(name, with)
    return unless RateLimits.enabled?

    limit = RateLimits.for(name)
    subject = rate_limit_subject(limit[:by])
    return if subject.blank?

    key = [ "rate-limit", name, limit[:by], subject ].join(":")
    count = Rails.cache.increment(key, 1, expires_in: limit[:within])
    return if count.nil? || count <= limit[:to]

    Rails.logger.info "[RateLimits] #{name} exceeded (#{count}/#{limit[:to]}) for #{limit[:by]}"
    instance_exec(&with)
  rescue StandardError => e
    # Cache unavailable, or anything else. Let it through.
    Rails.logger.warn "[RateLimits] #{name} check skipped: #{e.class} #{e.message}"
    nil
  end

  # What the count is keyed on. Blank means don't count at all — a sign-in form
  # submitted with no address is rejected on its own merits, and counting it
  # under a shared key would let one bad actor exhaust everyone's allowance.
  def rate_limit_subject(by)
    case by
    when :email then submitted_email
    else request.remote_ip
    end
  end

  def submitted_email
    params[:email].presence ||
      params.dig(:member, :email).presence ||
      params.dig(:session, :email).presence
  end
end
