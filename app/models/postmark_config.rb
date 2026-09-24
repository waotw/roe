class PostmarkConfig < ApplicationRecord
  TEST_CONFIG_PATH = File.join(RoeSitePaths::SITE_PATH, "system", "integrations", "postmark.yml")

  enum :mode, { test: 0, live: 1 }, prefix: true

  before_create :set_connected_at
  before_create :generate_webhook_token

  # AR Encryption — uses master.key
  encrypts :server_token
  encrypts :webhook_token
  # An Account API token can Manage Servers and read Sender Signatures across
  # the whole account — a much larger blast radius than a Server token. It is
  # kept ONLY in production (see store_account_token?), where the box is a
  # controlled server and the value can't be read back from the admin UI;
  # keeping it there powers the pre-emptive sender-signature check. Local never
  # writes it — the setup service uses the token in-request and discards it.
  encrypts :account_token

  # ── Singleton ────────────────────────────────────────────────────────────

  def self.current
    first_or_create!
  end

  def self.configured?
    current.connected?
  end

  # ── Token accessors ───────────────────────────────────────────────────────

  # Test token from file (all environments)
  def test_server_token
    test_config["server_token"]
  end

  # Live token from DB
  def live_server_token
    safe_encrypted_read(:server_token)
  end

  # The admin's live-key UI addresses every field as `<schema key>_live` — the
  # form input, the masking, and apply_live_keys all build that name. Postmark's
  # column is `server_token`, which is Postmark's own term and worth keeping, so
  # the model speaks the shared convention instead of the column being renamed
  # or Postmark being special-cased in three separate places.
  #
  # Without these, the page saved nothing, showed an empty field where a saved
  # token should read as bullets, and left Live Mode greyed out forever — all
  # from the same missing name, and all silently.
  def server_token_live
    live_server_token
  end

  def server_token_live=(value)
    self.server_token = value
  end

  # Whether Live Mode can be selected. StripeConfig has had this all along;
  # PostmarkConfig never did, and the view's `respond_to?(:live_mode_ready?) &&`
  # guard turned that into a permanently disabled radio button.
  def live_mode_ready?
    live_server_token.present?
  end

  # Active token based on mode — live wins in production when live token present
  def server_token
    if mode_live? && live_server_token.present?
      live_server_token
    else
      test_server_token.presence || live_server_token
    end
  end

  # ── Connection status ────────────────────────────────────────────────────

  def keys_present?
    server_token.present?
  end

  def connected?
    keys_present? && verified_at.present?
  end

  def live_mode?
    mode_live? && live_server_token.present?
  end

  def test_mode?
    test_server_token.present?
  end

  # ── API verification ─────────────────────────────────────────────────────

  def verify!
    return false unless keys_present?

    result = PostmarkService.test_connection(server_token)
    if result[:success]
      update_column(:verified_at, Time.current)
      true
    else
      update_column(:verified_at, nil)
      false
    end
  end

  # ── Sender verification ──────────────────────────────────────────────────
  #
  # verify! answers "does the token work". This answers "will Postmark accept
  # the address we send FROM", which is a different question with a different
  # failure: ErrorCode 400, "The 'From' address you supplied is not a Sender
  # Signature on your account."
  #
  # There's no way to ask without sending. Listing Sender Signatures needs an
  # Account API token and Roe only holds a Server token, so the check is a real
  # send — which means a successful one delivers a real email.
  #
  # The ADDRESS is stored rather than a status. "Verified" is then just "the
  # address that worked is the address we'd use now", so changing author_email
  # makes it unverified by itself — no reset hook to wire up or keep in step.

  # Postmark's code for an unconfirmed or unknown Sender Signature.
  SENDER_NOT_VERIFIED = 400

  def sender_verified?
    SiteSender.configured? && sender_verified_address == SiteSender.address
  end

  # A send was attempted and refused because of the From address. Only
  # meaningful for the address currently configured — once that changes, the
  # old failure says nothing about the new address.
  def sender_rejected? = sender_error.present? && !sender_verified?

  # Send a real message to prove the From address is accepted. Returns the
  # PostmarkService result so the caller can report what happened.
  def verify_sender!(to:)
    return { success: false, error: SiteSender::MISSING } unless SiteSender.configured?

    result = PostmarkService.send_transactional_email(
      to_email: to, to_name: to, tag: "sender-verification",
      subject: "Test email from #{SiteConfig.get('title').presence || 'your Roe site'}",
      html_content: "<p>This is a test. If you're reading it, Roe can send email " \
                    "from #{ERB::Util.html_escape(SiteSender.address)}.</p>"
    )

    if result[:success]
      update_columns(sender_verified_address: SiteSender.address, sender_error: nil)
    else
      update_columns(sender_verified_address: nil, sender_error: result[:error].to_s.presence)
    end

    result
  end

  # Called after a real send fails, so a rejection discovered in the wild
  # surfaces the same way a button press would.
  def record_sender_rejection!(error)
    update_columns(sender_verified_address: nil, sender_error: error.to_s.presence)
  end

  # ── Disconnect ───────────────────────────────────────────────────────────

  def disconnect!
    update!(
      server_token: nil,
      connected_at: nil,
      verified_at: nil
    )
    self.class.clear_test_config
  end

  # ── Webhook token ────────────────────────────────────────────────────────

  def regenerate_webhook_token!
    update!(webhook_token: SecureRandom.hex(32))
  end

  # Backfill the token on a record that never got one.
  #
  # generate_webhook_token is a before_create, so it only ever ran for records
  # made after it was added. An install whose PostmarkConfig row predates it —
  # PostmarkConfig.current is first_or_create!, so the row is made once and kept
  # forever — has no token, and nothing regenerates it.
  #
  # The admin hides the whole Webhook URL section when the token is blank
  # (the path is nil, so even the explanatory box is skipped), which reads as
  # "this install doesn't do webhooks" rather than "something is missing". So
  # repair it on the way in rather than waiting to be asked.
  def ensure_webhook_token!
    return webhook_token if safe_encrypted_read(:webhook_token).present?

    regenerate_webhook_token!
    Rails.logger.info "[PostmarkConfig] Backfilled a missing webhook token"
    webhook_token
  end

  # ── Account-API setup token ──────────────────────────────────────────────
  #
  # Whether this install may KEEP the account token. Production only: the token
  # can create and delete servers account-wide, so it's stored (encrypted) only
  # on a controlled server where it powers the ongoing pre-emptive signature
  # check. Local runs the same setup but discards the token afterwards — the
  # setup service is handed the token directly and never persists it here.
  def self.store_account_token? = Rails.env.production?

  def account_token_present?
    safe_encrypted_read(:account_token).present?
  end

  # The stored account token (production only), or nil. Used for the standing
  # sender-signature check; local always returns nil since it never stored one.
  def stored_account_token
    safe_encrypted_read(:account_token)
  end

  def store_account_token!(token)
    update!(account_token: token)
  end

  def remove_account_token!
    update!(account_token: nil)
  end

  # ── Webhook status ───────────────────────────────────────────────────────
  #
  # Two complementary checks, because "configured" and "working" aren't the
  # same thing:
  #
  #   webhook_configured? — a live, read-only API check that the webhook is
  #     REGISTERED and aimed at our URL (Postmark's side of the config). Cheap,
  #     no email. Confirms setup, NOT that a POST actually reaches us.
  #
  #   verify_webhooks!  — asks Postmark to test the endpoint on demand (POST
  #     /webhooks/{id}/verify): it POSTs a test of each enabled event type
  #     (Delivery, Bounce, SpamComplaint) to us and reports whether each got a
  #     200 — synchronously, no email, DKIM-independent. webhook_verified_at is
  #     stamped only when every webhook passes. This is the "it works" proof.

  # Registered with Postmark and pointing at `url`? Live API lookup, no send.
  def webhook_configured?(url)
    return false if url.blank? || server_token.blank?

    PostmarkService.webhook_for_url?(server_token, url)
  end

  def webhook_verified? = webhook_verified_at.present?

  # Run Postmark's on-demand verification for every Roe webhook at `url` and
  # stamp the result. Returns the service's { ok:, results:, error: } hash.
  def verify_webhooks!(url)
    result = PostmarkService.verify_webhooks(server_token, url)
    update_columns(webhook_verified_at: (result[:ok] ? Time.current : nil))
    result
  end

  # ── Test config file ─────────────────────────────────────────────────────

  def self.test_config
    return {} unless File.exist?(TEST_CONFIG_PATH)
    SiteFile.read_yaml(TEST_CONFIG_PATH)["test"] || {}
  rescue => e
    Rails.logger.error "Failed to load Postmark test config: #{e.message}"
    {}
  end

  def self.save_test_config(config_data)
    FileUtils.mkdir_p(File.dirname(TEST_CONFIG_PATH))
    SiteFile.write(TEST_CONFIG_PATH, { "test" => config_data }.to_yaml.sub(/\A---\s*\n/, ""))
  end

  def self.clear_test_config
    File.delete(TEST_CONFIG_PATH) if File.exist?(TEST_CONFIG_PATH)
  end

  # ── Decryption-failure tracking ──────────────────────────────────────────

  def decryption_errors
    @decryption_errors ||= Set.new
  end

  def decryption_failed?
    decryption_errors.any?
  end

  private

  def test_config
    self.class.test_config
  end

  def safe_encrypted_read(attr)
    self[attr]
  rescue ActiveRecord::Encryption::Errors::Decryption => e
    Rails.logger.warn "#{self.class.name}##{attr} decryption failed: #{e.message}"
    decryption_errors << attr
    nil
  end

  def generate_webhook_token
    return if safe_encrypted_read(:webhook_token).present?
    self.webhook_token = SecureRandom.hex(32)
  end

  def set_connected_at
    # Fire for both test (file) and live (DB) tokens
    self.connected_at ||= Time.current if test_config["server_token"].present? || safe_encrypted_read(:server_token).present?
  end
end
