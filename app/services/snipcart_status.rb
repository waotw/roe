# frozen_string_literal: true

# The Snipcart settings status checklist — mirrors PostmarkStatus / StripeStatus
# so all three integration pages read the same way.
#
# Snipcart has NO management or read API, so Roe knows far less here than it does
# for Stripe/Postmark. There is no key to verify and no webhook registration to
# read back (Snipcart can't be queried). The checklist is environment-split:
#
# LOCAL (development): the snippet works (browse/add-to-cart run on localhost),
# but order COMPLETION is inherently live-only — Snipcart crawls the product URL
# over the public internet to validate each order, which can't reach localhost.
# So local shows connection + mode + one "orders complete on your live site" info
# row, and NOT the webhook-received/domain rows (which compare live config and
# would falsely claim "matches"/"todo").
#
# LIVE (production): the honest signals are:
#   - connection: is the active-mode snippet present
#   - mode: test vs. live
#   - webhook: has Roe actually RECEIVED a Snipcart order webhook for this mode?
#     That's the only proof the manual URL paste worked — orders arriving IS the
#     confirmation, since Snipcart won't tell us whether the hook is registered.
#   - domain: Snipcart's order validation crawls the product URL, which must be
#     on the store's configured default domain; a mismatch with the site URL is
#     the classic cause of "checkout spins".
class SnipcartStatus
  include WebhookUrlHelper

  Item = Struct.new(:key, :label, :state, :detail, keyword_init: true)
  # state ∈ :ok (green ✓) / :todo (amber, action needed) / :warn (red, broken)
  #        / :unknown (grey) / :info (neutral fact)

  def self.for(config = SnipcartConfig.current, ui_production: Rails.env.production?)
    new(config, ui_production:).items
  end

  def initialize(config, ui_production: Rails.env.production?)
    @sc = config
    @ui_production = ui_production
  end

  def items
    return local_items unless @ui_production

    [ connection, mode, webhook, domain ].compact
  end

  private

  # Local (development): the snippet genuinely works — browse and add-to-cart run
  # on localhost. But completing an order can't happen locally in ANY mode:
  # Snipcart validates each order by crawling the product URL over the public
  # internet, which can't reach localhost, so order completion and its webhook
  # are inherently live-only. So don't show the webhook-received or domain rows
  # (both compare live config and would falsely claim "matches" / "todo") — just
  # say plainly where orders complete. Mirrors how Stripe/Postmark say "activates
  # on your live site".
  def local_items
    [
      connection,
      mode,
      info(:local, "Orders complete on your live site",
           "Browse and add-to-cart work locally, but Snipcart validates each order " \
           "by crawling your live site on the public internet — Deploy your site to test and process real orders.")
    ].compact
  end

  def connection
    if @sc.connected?
      ok(:connection, "Snipcart snippet connected", "Your #{@sc.mode} snippet is in place.")
    elsif @sc.keys_present?
      todo(:connection, "Snippet not verified", "A snippet is saved but hasn't been verified — save it again.")
    else
      todo(:connection, "Not connected", "Add your Snipcart snippet below.")
    end
  end

  def mode
    live = @sc.mode_live?
    state = @sc.connected? ? :ok : :info
    Item.new(key: :mode, label: "Mode: #{live ? 'Live' : 'Test'}", state: state,
             detail: live ? "Real orders." : "Test mode — use Snipcart test cards, no real orders.")
  end

  # Snipcart gives no way to check whether the webhook is registered, so the
  # only honest proof is an order actually arriving. "Have we received one for
  # this mode" is the signal; the URL to paste lives on the page.
  def webhook
    return nil unless @sc.keys_present?

    received = SnipcartOrder.for_mode(@sc.mode).exists?
    if received
      ok(:webhook, "Order webhook working", "Roe has received #{@sc.mode}-mode orders from Snipcart.")
    elsif snipcart_webhook_url.present?
      todo(:webhook, "No orders received yet",
           "Paste the webhook URL below into Snipcart (Store Configurations → Webhooks). Orders appear here once one comes through.")
    else
      info(:webhook, "Webhook activates on your live site",
           "Snipcart can't reach localhost. Deploy, or set a dev tunnel host, then paste the URL into Snipcart.")
    end
  end

  # Snipcart's order validation crawls the product URL, which must sit on the
  # store's configured default domain. A mismatch with the site URL is the usual
  # "checkout spins / product URL unreachable" cause — flag it when both are known.
  def domain
    configured = @sc.default_domain.to_s.strip.presence
    return nil if configured.blank?

    site = site_host
    return info(:domain, "Store domain: #{configured}", nil) if site.blank?

    if host_of(configured) == site
      ok(:domain, "Store domain matches your site", configured)
    else
      warn(:domain, "Store domain doesn't match your site",
           "Snipcart validates orders against #{configured}, but your site is #{site}. " \
           "Checkout can fail if they differ — update the store's default domain or your Site URL.")
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  def ok(key, label, detail)   = Item.new(key: key, label: label, state: :ok, detail: detail)
  def todo(key, label, detail) = Item.new(key: key, label: label, state: :todo, detail: detail)
  def info(key, label, detail) = Item.new(key: key, label: label, state: :info, detail: detail)
  def warn(key, label, detail) = Item.new(key: key, label: label, state: :warn, detail: detail)

  def site_host
    host_of(SiteConfig.site_url)
  rescue StandardError
    nil
  end

  def host_of(value)
    v = value.to_s.strip
    return nil if v.blank?
    v = "https://#{v}" unless v.match?(%r{\Ahttps?://})
    URI.parse(v).host&.downcase&.sub(/\Awww\./, "")
  rescue URI::InvalidURIError
    nil
  end
end
