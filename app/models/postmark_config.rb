class PostmarkConfig < ApplicationRecord
  TEST_CONFIG_PATH = File.join(RoeSitePaths::SITE_PATH, "system", "integrations", "postmark.yml")

  enum :mode, { test: 0, live: 1 }, prefix: true

  before_create :set_connected_at
  before_create :generate_webhook_token

  # AR Encryption — uses master.key
  encrypts :server_token
  encrypts :webhook_token

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

  # ── Test config file ─────────────────────────────────────────────────────

  def self.test_config
    return {} unless File.exist?(TEST_CONFIG_PATH)
    YAML.load_file(TEST_CONFIG_PATH)["test"] || {}
  rescue => e
    Rails.logger.error "Failed to load Postmark test config: #{e.message}"
    {}
  end

  def self.save_test_config(config_data)
    FileUtils.mkdir_p(File.dirname(TEST_CONFIG_PATH))
    File.write(TEST_CONFIG_PATH, { "test" => config_data }.to_yaml.sub(/\A---\s*\n/, ""))
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
