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
             detail: live ? "Real email is sent." : "Sandbox — nothing is delivered.")
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

  def webhook
    if @pm.webhook_verified?
      ok(:webhook, "Webhook confirmed", "Postmark reached your site with a delivery event.")
    elsif @pm.webhook_probe_message_id.present?
      Item.new(key: :webhook, label: "Webhook — waiting for confirmation", state: :unknown,
               detail: "A test was sent; the delivery callback hasn't arrived yet.")
    elsif !webhooks_reachable?
      # Local without a public tunnel host: Postmark can't call back to
      # localhost, so no webhook can be created or tested here. Not a to-do the
      # user can act on from this machine — say where it happens instead.
      Item.new(key: :webhook, label: "Webhook — set up on your live site", state: :info,
               detail: "Postmark can't reach localhost, so webhooks are configured when you " \
                       "run this on your deployed site. To test them here, set a dev_host tunnel.")
    else
      Item.new(key: :webhook, label: "Webhook not set up", state: :todo,
               detail: "Run the setup below to connect and test the delivery webhook.")
    end
  end

  # Whether Postmark could POST a webhook to this install — false on localhost
  # without a dev tunnel host, true in production (the live domain).
  def webhooks_reachable?
    webhook_url("/webhooks/postmark/probe").present?
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
      "Run setup, or send a test, to check it." :
      "Full sender and DKIM checks run on your deployed site; here, send a test to confirm the address."
  end

  def missing_sender
    Item.new(key: :sender, label: "No sender address set", state: :warn,
             detail: "Add an Author Email in Settings → Site so Roe has an address to send from.")
  end

  def ok(key, label, detail)   = Item.new(key:, label:, state: :ok,   detail:)
  def todo(key, label, detail) = Item.new(key:, label:, state: :todo, detail:)
end
