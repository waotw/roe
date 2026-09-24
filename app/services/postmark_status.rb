# frozen_string_literal: true

# The Postmark settings status checklist — one honest list of "what's needed to
# make email work, and where each piece stands". Assembled from what Roe already
# knows (connection, mode, reactive sender state, webhook round-trip) plus, when
# a production account token is stored, a LIVE read of the sender signature so
# the address / DKIM / Return-Path rows are pre-emptive rather than reactive.
#
# The live read is one API call and only happens on the Postmark settings page
# (not every admin render — see WebhookUrlHelper's note), and is rescued to an
# :unknown row so a Postmark hiccup never breaks the page.
class PostmarkStatus
  # webhook_url / webhook_base_url live here (no view context needed) so the
  # webhook row can tell whether Postmark could actually reach this install —
  # nil locally without a dev tunnel host, the live domain in production.
  include WebhookUrlHelper

  Item = Struct.new(:key, :label, :state, :detail, keyword_init: true)
  # state ∈ :ok (green ✓) / :todo (amber, action needed) / :warn (red, broken)
  #        / :unknown (grey, couldn't determine) / :info (neutral fact)

  def self.for(config = PostmarkConfig.current)
    new(config).items
  end

  def initialize(config)
    @pm = config
    @sender = SiteSender.address
  end

  def items
    [ connection, mode, sender_address, dkim, return_path, webhook ].compact
  end

  private

  def connection
    if @pm.connected?
      Item.new(key: :connection, label: "Connected to Postmark", state: :ok,
               detail: "Your server token works.")
    elsif @pm.keys_present?
      Item.new(key: :connection, label: "Postmark token not verified", state: :warn,
               detail: "A token is saved but Postmark didn't accept it.")
    else
      Item.new(key: :connection, label: "Not connected", state: :todo,
               detail: "Set Postmark up below.")
    end
  end

  def mode
    return nil unless @pm.respond_to?(:mode)

    live = @pm.mode_live?
    Item.new(key: :mode, label: "Mode: #{live ? 'Live' : 'Test'}", state: :info,
             detail: live ? "Real email is sent." : "Sandbox — Check Activity on Postmark to confirm.")
  end

  # Sender address (the one thing a send actually requires). Pre-emptive when a
  # live signature read is available; otherwise the reactive "a real send was
  # accepted" state, which is all a server token can know.
  def sender_address
    return missing_sender unless @sender.present?

    if (d = live_sender_detail)
      d[:confirmed] ?
        ok(:sender, "Sender address confirmed", @sender) :
        todo(:sender, "Sender address not confirmed",
             "Confirm #{@sender} in Postmark — click the link in the confirmation email.")
    elsif @pm.sender_verified?
      ok(:sender, "Sender address confirmed", @sender)
    elsif @pm.sender_rejected?
      todo(:sender, "Sender address rejected", "Postmark refused #{@sender}. Confirm it as a Sender Signature.")
    else
      Item.new(key: :sender, label: "Sender address not checked yet", state: :unknown,
               detail: reactive_hint)
    end
  end

  def dkim
    return nil unless (d = live_sender_detail)

    d[:dkim_verified] ?
      ok(:dkim, "DKIM verified", "Your domain is authenticated for deliverability.") :
      todo(:dkim, "DKIM not set up", "Add Postmark's DKIM DNS record to improve deliverability.")
  end

  def return_path
    return nil unless (d = live_sender_detail)

    d[:return_path_verified] ?
      ok(:return_path, "Return-Path verified", nil) :
      todo(:return_path, "Return-Path not set up", "Optional, but improves deliverability.")
  end

  # Webhook status. Production: verified working (Postmark's on-demand check
  # passed) or not-yet-verified once registered — the RE-CHECK button lives in
  # the Postmark Setup section, so here we just report state. Local never needs
  # the webhook working (it activates on the live site), so it's informational.
  def webhook
    return local_webhook unless Rails.env.production?

    if @pm.webhook_verified?
      ok(:webhook, "All webhooks verified", "Postmark can reach your site — deliveries, bounces, and spam complaints.")
    elsif configured_webhook_url && @pm.webhook_configured?(configured_webhook_url)
      todo(:webhook, "Webhooks not verified", "Registered with Postmark. Use RE-CHECK in Postmark Setup to confirm they reach your site.")
    else
      todo(:webhook, "Webhooks not set up", "Run Postmark Setup below to connect the webhook.")
    end
  end

  # Local never needs the webhook working — it activates on the live site. Say
  # so, split by whether a live site exists yet, and never nag to "run setup".
  # Nothing to report until the sandbox is actually set up (the connection row
  # already covers "not connected"), so omit the row otherwise.
  def local_webhook
    return nil unless @pm.keys_present?

    detail = live_site_deployed? ?
      "They activate on your live site — run Postmark Setup on the live site to enable them." :
      "They activate on your live site — run Postmark Setup on the live site to enable them once you've deployed."
    Item.new(key: :webhook, label: "Webhooks created", state: :info, detail: detail)
  end

  # The URL the account-setup webhook was pointed at, or nil if we can't build
  # one (no token yet, or no reachable base — production always has the domain).
  def configured_webhook_url
    token = @pm.webhook_token
    return nil if token.blank?

    webhook_url("/webhooks/postmark/#{token}")
  end

  # Has this install heard from a deployed peer recently (Site Sync's signal)?
  def live_site_deployed?
    SiteSync::Exchange.can_call_peer? && SiteSync::Exchange.peer_reachable?
  rescue StandardError
    false
  end

  # ── Live signature read (production, memoised for one render) ─────────────

  def live_sender_detail
    return @detail if defined?(@detail)

    token = @pm.stored_account_token
    @detail = (token && @sender.present?) ? PostmarkAccountSetup.new(token).sender_detail(@sender) : nil
  rescue StandardError => e
    Rails.logger.warn "[PostmarkStatus] signature read failed: #{e.message}"
    @detail = nil
  end

  def reactive_hint
    PostmarkConfig.store_account_token? ?
      "Run setup, or send a test email, to check it." :
      "Full sender and DKIM checks run on your deployed site; on the local site, send a test to confirm the address."
  end

  def missing_sender
    Item.new(key: :sender, label: "No sender address set", state: :warn,
             detail: "Add an Author Email in Settings → Site so Roe has an address to send emails from.")
  end

  def ok(key, label, detail)   = Item.new(key:, label:, state: :ok,   detail:)
  def todo(key, label, detail) = Item.new(key:, label:, state: :todo, detail:)
end
