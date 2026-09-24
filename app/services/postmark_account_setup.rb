# frozen_string_literal: true

require "net/http"
require "json"

# "Have Roe set up your Postmark integration."
#
# Given an Account API token, this creates (or reuses) the sandbox and live
# servers, reads back their Server tokens, points a webhook at Roe, and reads
# the account's Sender Signature state. It NEVER persists the account token —
# the caller (the controller) decides what to keep: sandbox token → the
# plaintext test yml, live token → the encrypted DB (production) or the peer
# (Path B, later). See PostmarkConfig#store_account_token?.
#
# Server tokens are a property of the Postmark account, not the environment, so
# whichever side runs this reads back the same tokens. That's what lets a local
# run seed the sandbox and a production run seed both without any value having
# to travel between them.
#
# Auth split (Postmark's, not ours):
#   - account token  → Manage Servers, list Sender Signatures  (X-Postmark-Account-Token)
#   - server token   → that server's webhooks                  (X-Postmark-Server-Token)
class PostmarkAccountSetup
  API_BASE = "https://api.postmarkapp.com"

  # Postmark seeds every account with a default server. There is no "is default"
  # flag on the servers API, so it's matched by its stock name; a user may have
  # renamed it (then it just looks like any other named server, which is fine)
  # or named a real server this (rare — worst case we offer it for reuse). Its
  # streams are the stock Default Broadcast/Transactional/Inbound; left alone.
  DEFAULT_SERVER_NAME = "My First Server"

  Result = Struct.new(:ok, :error, :servers, :sandbox, :live, :signatures, keyword_init: true) do
    def ok? = ok
  end

  # One created/reused server: which token to store and where it came from.
  Server = Struct.new(:id, :name, :token, :delivery_type, :created, :webhook, keyword_init: true)

  def initialize(account_token)
    @account_token = account_token.to_s.strip
  end

  # ── Listing (for the reuse-or-create decision) ───────────────────────────

  # Every server on the account, each as { id:, name:, delivery_type:, default: }.
  # The controller filters out the default to decide whether to even offer a
  # reuse choice (default-only → no choice; other servers exist → offer them).
  def list_servers
    body = account_get("/servers?count=500&offset=0")
    Array(body["Servers"]).map do |s|
      {
        id: s["ID"], name: s["Name"],
        delivery_type: s["DeliveryType"],
        default: default_server?(s)
      }
    end
  end

  def default_server?(server)
    server["Name"].to_s.strip == DEFAULT_SERVER_NAME
  end

  # ── Server creation / reuse ──────────────────────────────────────────────

  # Ensure a server of the given kind exists and hand back its token.
  #
  #   kind      — :sandbox or :live (fixes DeliveryType, which Postmark won't
  #               let us change after creation)
  #   name      — the server name to create ("<Site> - Sandbox" / " - Production")
  #   reuse_id  — when set, adopt that existing server instead of creating one
  #               (the "use my existing server" branch); its DeliveryType is
  #               whatever it already is — we don't try to convert it.
  def ensure_server(kind:, name:, reuse_id: nil)
    if reuse_id
      s = account_get("/servers/#{reuse_id}")
      return Server.new(
        id: s["ID"], name: s["Name"], token: first_token(s),
        delivery_type: s["DeliveryType"], created: false
      )
    end

    s = account_post("/servers", {
      Name: name,
      DeliveryType: (kind == :sandbox ? "Sandbox" : "Live"),
      Color: (kind == :sandbox ? "Yellow" : "Green")
    })
    Server.new(
      id: s["ID"], name: s["Name"], token: first_token(s),
      delivery_type: s["DeliveryType"], created: true
    )
  end

  # ── Webhook (server-token scoped) ────────────────────────────────────────
  #
  # Point the server at `url` for Delivery + Bounce + SpamComplaint, on BOTH
  # message streams: `outbound` (sign-in links, and the delivery-verification
  # probe) and `broadcast` (newsletters — where bounces and spam matter most).
  # A single-stream webhook was the bug: newsletter bounces went to broadcast,
  # which had no webhook, and the probe's Delivery event went to outbound.
  #
  # Postmark verifies the endpoint on create (POSTs a test that must 200), so
  # this both creates AND proves reachability — which is why it can't run
  # against a localhost URL. Returns { ok:, streams: {..}, error: } and never
  # raises: a webhook failure shouldn't lose the server tokens already read.
  WEBHOOK_STREAMS = %w[outbound broadcast].freeze

  def ensure_webhook(server_token, url)
    return { ok: false, error: "No reachable webhook URL for this environment" } if url.to_s.empty?

    streams = {}
    WEBHOOK_STREAMS.each { |stream| streams[stream] = ensure_webhook_for_stream(server_token, url, stream) }
    { ok: streams.values.all? { |s| s[:ok] }, streams: streams }
  rescue Error => e
    { ok: false, error: e.message }
  end

  def ensure_webhook_for_stream(server_token, url, stream)
    existing = server_get(server_token, "/webhooks?MessageStream=#{stream}")
    hook = Array(existing["Webhooks"]).find { |w| w["Url"] == url }
    return { ok: true, id: hook["ID"], reused: true } if hook

    created = server_post(server_token, "/webhooks", {
      Url: url,
      MessageStream: stream,
      Triggers: {
        Delivery: { Enabled: true },
        Bounce: { Enabled: true, IncludeContent: true },
        SpamComplaint: { Enabled: true, IncludeContent: true }
      }
    })
    { ok: true, id: created["ID"], reused: false }
  rescue Error => e
    { ok: false, error: e.message }
  end

  # ── Sender Signatures (account-token scoped) ─────────────────────────────
  #
  # The real reason to hold an account token: ask whether the From address is
  # authorised BEFORE anyone sends, instead of catching a 400 after the first
  # sign-in email fails. Returns the raw signature list so the UI can show real
  # state (Confirmed / pending / DKIM) rather than describe Postmark's rules.
  def sender_signatures
    body = account_get("/senders?count=500&offset=0")
    Array(body["SenderSignatures"]).map do |s|
      {
        id: s["ID"], email: s["EmailAddress"], name: s["Name"], domain: s["Domain"],
        confirmed: s["Confirmed"] == true
      }
    end
  end

  # Full detail for the signature matching `email` (case-insensitive), or nil.
  # The list endpoint omits DKIM/Return-Path; only the detail endpoint carries
  # them, so the deliverability rows need this second call. Confirmed authorises
  # the one address (what a send requires); DKIMVerified / ReturnPathDomain
  # authorise the domain (what deliverability depends on) — Postmark's own
  # distinction, read live rather than described in copy.
  def sender_detail(email)
    match = sender_signatures.find { |s| s[:email].to_s.casecmp?(email.to_s) }
    return nil unless match

    d = account_get("/senders/#{match[:id]}")
    {
      email: d["EmailAddress"], confirmed: d["Confirmed"] == true,
      dkim_verified: d["DKIMVerified"] == true,
      return_path_verified: d["ReturnPathDomainVerified"] == true
    }
  end

  # ── HTTP ─────────────────────────────────────────────────────────────────

  class Error < StandardError; end

  private

  def first_token(server) = Array(server["ApiTokens"]).first

  def account_get(path)  = request(:get,  path, account_header)
  def account_post(p, b) = request(:post, p,    account_header, b)

  def server_get(token, path)  = request(:get,  path, server_header(token))
  def server_post(token, p, b) = request(:post, p,    server_header(token), b)

  def account_header = { "X-Postmark-Account-Token" => @account_token }
  def server_header(token) = { "X-Postmark-Server-Token" => token }

  def request(method, path, auth_header, body = nil)
    uri = URI("#{API_BASE}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    req = (method == :post ? Net::HTTP::Post : Net::HTTP::Get).new(uri.request_uri)
    req["Accept"] = "application/json"
    auth_header.each { |k, v| req[k] = v }
    if body
      req["Content-Type"] = "application/json"
      req.body = body.to_json
    end

    res = http.request(req)
    parsed = JSON.parse(res.body) rescue {}
    # Postmark uses 422 for API misuse with an ErrorCode + Message; 401 for a
    # bad token. Surface the Message — it's written for humans and names the
    # real problem ("Invalid account token", "Server names must be unique").
    unless res.code.to_i.between?(200, 299)
      raise Error, (parsed["Message"].presence || "Postmark returned #{res.code}")
    end
    parsed
  rescue Error
    raise
  rescue => e
    raise Error, e.message
  end
end
