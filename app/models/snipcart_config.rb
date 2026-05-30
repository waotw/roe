class SnipcartConfig < ApplicationRecord
  TEST_CONFIG_PATH = File.join(RoeSitePaths::SITE_PATH, "system", "integrations", "snipcart.yml")

  enum :mode, { test: 0, live: 1 }, prefix: true

  validates :mode, presence: true

  before_create :set_connected_at

  # AR Encryption — uses master.key
  encrypts :api_key_test
  encrypts :api_key_live

  # ── Singleton ────────────────────────────────────────────────────────────

  def self.current
    first_or_create!(mode: :test)
  end

  # ── Key accessors ─────────────────────────────────────────────────────────

  def api_key_test
    test_config["api_key"].presence || self[:api_key_test]
  end

  def api_key_live
    self[:api_key_live]
  end

  # Active key based on mode
  def current_api_key
    mode_test? ? api_key_test : api_key_live
  end

  # ── Connection status ────────────────────────────────────────────────────

  def keys_present?
    current_api_key.present?
  end

  # Verified = keys present AND last API check succeeded
  def connected?
    keys_present? && verified_at.present?
  end

  def live_mode_ready?
    api_key_live.present?
  end

  # ── API verification ─────────────────────────────────────────────────────

  def verify!
    return false unless keys_present?

    # Use Snipcart orders endpoint — returns 401 on bad key, 200 on valid
    uri = URI("https://app.snipcart.com/api/orders?limit=1")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 10

    request = Net::HTTP::Get.new(uri)
    # Snipcart uses HTTP Basic auth with api_key as username, empty password
    request.basic_auth(current_api_key, "")
    request["Accept"] = "application/json"

    response = http.request(request)

    if response.code.to_i == 200
      update_column(:verified_at, Time.current)
      true
    else
      update_column(:verified_at, nil)
      false
    end
  rescue => e
    Rails.logger.error "Snipcart verification failed: #{e.message}"
    update_column(:verified_at, nil)
    false
  end

  # ── Disconnect ───────────────────────────────────────────────────────────

  def disconnect!
    update!(
      api_key_test: nil,
      api_key_live: nil,
      connected_at: nil,
      verified_at: nil
    )
    self.class.clear_test_config
  end

  # ── Store settings (delegated to store.yml) ──────────────────────────────

  def currency
    SiteConfig.feature("store", "currency") || "usd"
  end

  def default_domain
    SiteConfig.feature("store", "default_domain")
  end

  def load_strategy
    SiteConfig.feature("store", "snipcart.load_strategy") || "on-user-interaction"
  end

  def modal_style
    SiteConfig.feature("store", "snipcart.modal_style") || "side"
  end

  # ── Test config file ─────────────────────────────────────────────────────

  def self.test_config
    return {} unless File.exist?(TEST_CONFIG_PATH)
    YAML.load_file(TEST_CONFIG_PATH)["test"] || {}
  rescue => e
    Rails.logger.error "Failed to load Snipcart test config: #{e.message}"
    {}
  end

  def self.save_test_config(config_data)
    FileUtils.mkdir_p(File.dirname(TEST_CONFIG_PATH))
    File.write(TEST_CONFIG_PATH, { "test" => config_data }.to_yaml)
  end

  def self.clear_test_config
    File.delete(TEST_CONFIG_PATH) if File.exist?(TEST_CONFIG_PATH)
  end

  private

  def test_config
    self.class.test_config
  end

  def set_connected_at
    self.connected_at ||= Time.current if current_api_key.present?
  end
end
