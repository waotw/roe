# Computes absolute URLs that external services (Stripe, Postmark, etc.)
# should POST webhooks to. Resolves environment differences in one place:
#
#   - production / staging / any non-dev environment
#       → SiteConfig.site_url (the live domain)
#   - development / test with `dev_host:` set in development.yml
#       → that host (explicit override; always wins when present)
#   - development / test with no `dev_host:` but `allowed_hosts:`
#     contains a public-looking hostname
#       → the first such entry. Users already add their ngrok /
#         cloudflared host to allowed_hosts so Rails' Host
#         Authorization accepts inbound requests from it; reusing
#         that value means most setups need zero extra config.
#   - development / test with neither
#       → nil
#
# Returning nil signals "this integration can't be tested locally
# right now". Integration views check for nil and render a
# tunnel-required helper instead of a useless localhost URL that
# external services can't reach.
#
# Why no ngrok auto-detect (via 127.0.0.1:4040/api/tunnels) yet:
# kept the helper deterministic and zero-network-call to avoid log
# noise on every admin page render. Easy to add later behind a
# cached lookup once the manual config UX shows real friction.
module WebhookUrlHelper
  def webhook_url(path)
    base = webhook_base_url
    return nil if base.nil? || base.empty?
    "#{base}#{path}"
  end

  private

  def webhook_base_url
    if Rails.env.development? || Rails.env.test?
      host = explicit_dev_host || inferred_dev_host
      return nil if host.nil? || host.empty?
      host.match?(/\Ahttps?:\/\//) ? host : "https://#{host}"
    else
      SiteConfig.site_url
    end
  end

  def explicit_dev_host
    SiteConfig.development("dev_host").to_s.strip.presence
  end

  # Walks allowed_hosts looking for the first public-looking
  # hostname (a String with a dot, not localhost/127.0.0.1).
  # Skips Regexp entries and any localhost-shaped strings since
  # those don't help an external service call back to you.
  def inferred_dev_host
    Array(SiteConfig.development("allowed_hosts")).each do |entry|
      next unless entry.is_a?(String)
      h = entry.strip
      next if h.empty?
      next if h.match?(/\Alocalhost(:|\z)/i) || h.start_with?("127.0.0.1")
      next unless h.include?(".")
      return h
    end
    nil
  end
end
