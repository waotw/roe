# frozen_string_literal: true

# The Stripe settings status checklist — one honest list of "what's needed to
# take payments, and where each piece stands." Mirrors PostmarkStatus so the
# two integration pages read the same way.
#
# What Stripe lets Roe know differs from Postmark: there's no account-token
# read-back, so every signal here comes from the keys the user pasted plus the
# webhook registration check. The webhook row is environment-aware for the same
# reason as Postmark's — a real event can't reach localhost, so local is
# informational, production reports registered/working.
class StripeStatus
  include WebhookUrlHelper

  Item = Struct.new(:key, :label, :state, :detail, keyword_init: true)
  # state ∈ :ok (green ✓) / :todo (amber, action needed) / :warn (red, broken)
  #        / :unknown (grey) / :info (neutral fact)

  def self.for(config = StripeConfig.current, ui_production: Rails.env.production?)
    new(config, ui_production:).items
  end

  def initialize(config, ui_production: Rails.env.production?)
    @sc = config
    @ui_production = ui_production
  end

  def items
    [ connection, mode, webhook ].compact
  end

  private

  def connection
    if @sc.connected?
      Item.new(key: :connection, label: "Connected to Stripe", state: :ok,
               detail: "Your #{@sc.mode} secret key works.")
    elsif @sc.keys_present?
      Item.new(key: :connection, label: "Stripe key not verified", state: :warn,
               detail: "A key is saved but Stripe didn't accept it. Check the key and its permissions.")
    else
      Item.new(key: :connection, label: "Not connected", state: :todo,
               detail: "Add your Stripe restricted key below.")
    end
  end

  def mode
    live = @sc.mode_live?
    # A working setup is a working setup — ✓ once the key verifies, not a neutral
    # dot. Matches PostmarkStatus. The detail still says what the mode means.
    state = @sc.connected? ? :ok : :info
    Item.new(key: :mode, label: "Mode: #{live ? 'Live' : 'Test'}", state: state,
             detail: live ? "Real charges are taken." : "Test mode — use Stripe test cards, no real charges.")
  end

  # The publishable key is intentionally not tracked: Roe uses hosted Stripe
  # Checkout (server-side redirect), never Stripe.js in the browser, so a
  # publishable key is never needed. Only the restricted/secret key matters.

  # Webhook: production reports registered/verified; local is informational
  # because a real event can't reach localhost without a tunnel. Nothing to
  # report until keys are present (the connection row covers "not connected").
  def webhook
    return nil unless @sc.keys_present?

    url = configured_webhook_url
    return local_webhook(url) unless @ui_production

    if url.blank?
      todo(:webhook, "Webhook not set up", "Deploy your site, then set up the webhook below.")
    elsif @sc.current_webhook_signing_secret.present? && @sc.webhook_configured?(url)
      ok(:webhook, "Webhook active", "Registered with Stripe and its signing secret is saved.")
    elsif @sc.webhook_configured?(url)
      todo(:webhook, "Webhook registered, secret missing",
           "An endpoint exists but Roe has no signing secret. Use “Set up webhook” below to refresh it.")
    else
      todo(:webhook, "Webhook not set up", "Use “Set up webhook” below to connect it.")
    end
  end

  def local_webhook(url)
    if url.present?
      # A dev tunnel host is configured, so local setup can actually run.
      if @sc.current_webhook_signing_secret.present? && @sc.webhook_configured?(url)
        ok(:webhook, "Webhook active (local tunnel)", "Registered at your dev host and signing secret saved.")
      else
        todo(:webhook, "Webhook not set up", "Your dev tunnel host is set — use “Set up webhook” below to connect it.")
      end
    else
      info(:webhook, "Webhook activates on your live site",
           "Stripe can't reach localhost. Set a dev tunnel host to test it locally, or set it up on your deployed site.")
    end
  end

  # ── Item helpers ─────────────────────────────────────────────────────────

  def ok(key, label, detail)      = Item.new(key: key, label: label, state: :ok, detail: detail)
  def todo(key, label, detail)    = Item.new(key: key, label: label, state: :todo, detail: detail)
  def info(key, label, detail)    = Item.new(key: key, label: label, state: :info, detail: detail)

  def configured_webhook_url
    webhook_url("/webhooks/stripe")
  rescue StandardError
    nil
  end
end
