require "test_helper"
require "ostruct"

class Admin::ConfigsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.take
    sign_in_as(@user)

    # Clean slate for integration records
    StripeConfig.delete_all
    PostmarkConfig.delete_all
    SnipcartConfig.delete_all

    # Ensure feature config files exist so integrations show up.
    # Safe — paths route to tmp/test_site/ under RAILS_ENV=test
    # (see config/application.rb), not the real /site directory.
    ensure_feature_file("members.yml")
    ensure_feature_file("store.yml")
  end

  # ── Index ──────────────────────────────────────────────────────────────────

  test "index lists integrations when features are enabled" do
    get admin_configs_path
    assert_response :success
    assert_select "a[href=?]", admin_edit_payments_config_path
    assert_select "a[href=?]", admin_edit_newsletters_config_path
    assert_select "a[href=?]", admin_edit_snipcart_integration_config_path
  end

  # ── Payments (Stripe) ────────────────────────────────────────────────────

  test "edit_payments renders the integration form" do
    get admin_edit_payments_config_path
    assert_response :success
    assert_select "form[action=?]", admin_payments_config_path
  end

  test "update_payments writes test keys to YAML and syncs" do
    patch admin_payments_config_path, params: {
      test: {
        publishable_key: "pk_test_123",
        secret_key: "sk_test_123",
        webhook_signing_secret: "whsec_test_123"
      }
    }

    assert_redirected_to admin_edit_payments_config_path
    assert_equal "Stripe configuration saved", flash[:notice]

    # Verify YAML file was written
    path = File.join(SiteConfig::INTEGRATIONS_PATH, "stripe.yml")
    assert File.exist?(path)
    yaml = YAML.load_file(path)
    assert_equal "pk_test_123", yaml["test"]["publishable_key"]
    assert_equal "sk_test_123", yaml["test"]["secret_key"]

    # Verify StripeConfig picked up the test keys
    stripe = StripeConfig.current
    assert_equal "pk_test_123", stripe.publishable_key_test
    assert_equal "sk_test_123", stripe.secret_key_test
  end

  test "update_payments skips masked placeholder values" do
    # Pre-seed stripe.yml with existing values
    FileUtils.mkdir_p(SiteConfig::INTEGRATIONS_PATH)
    File.write(
      File.join(SiteConfig::INTEGRATIONS_PATH, "stripe.yml"),
      { "test" => { "publishable_key" => "pk_test_existing", "secret_key" => "sk_test_old" } }.to_yaml
    )

    # Submit placeholder for publishable_key and new secret_key
    patch admin_payments_config_path, params: {
      test: {
        publishable_key: "••••••••••••••••",
        secret_key: "sk_test_new"
      }
    }

    assert_redirected_to admin_edit_payments_config_path

    # Verify stripe.yml preserves old publishable_key and updates secret_key
    stripe_yaml = YAML.load_file(File.join(SiteConfig::INTEGRATIONS_PATH, "stripe.yml"))
    assert_equal "pk_test_existing", stripe_yaml["test"]["publishable_key"]
    assert_equal "sk_test_new",      stripe_yaml["test"]["secret_key"]
  end

  test "update_payments_live redirects in non-production" do
    patch admin_live_payments_config_path, params: {
      live: { publishable_key: "pk_live_123", secret_key: "sk_live_123" }
    }

    assert_redirected_to admin_edit_payments_config_path
    assert_equal "Live keys are only saved in production.", flash[:notice]
  end

  test "update_payments_mode switches mode to live when live keys present" do
    stripe = StripeConfig.current
    stripe.update!(
      publishable_key_live: "pk_live_123",
      secret_key_live: "sk_live_123",
      verified_at: Time.current
    )

    patch admin_mode_payments_config_path, params: { mode: "live" }

    assert_redirected_to admin_edit_payments_config_path
    assert_equal "Payments mode set to Live", flash[:notice]
    assert stripe.reload.mode_live?
  end

  test "update_payments_mode rejects live without live keys" do
    patch admin_mode_payments_config_path, params: { mode: "live" }

    assert_redirected_to admin_edit_payments_config_path
    assert_equal "Add live keys before switching to Live mode", flash[:error]
    assert StripeConfig.current.mode_test?
  end

  test "disconnect_payments clears all keys" do
    stripe = StripeConfig.current
    stripe.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123",
      publishable_key_live: "pk_live_123",
      secret_key_live: "sk_live_123",
      verified_at: Time.current
    )
    StripeConfig.save_test_config("publishable_key" => "pk_test_123")

    delete admin_disconnect_payments_config_path

    assert_redirected_to admin_edit_payments_config_path
    assert_equal "Stripe disconnected. All keys cleared.", flash[:notice]

    stripe.reload
    assert_nil stripe.publishable_key_test
    assert_nil stripe.secret_key_test
    assert_nil stripe.publishable_key_live
    assert_nil stripe.secret_key_live
    assert_nil stripe.verified_at
    assert_not File.exist?(StripeConfig::TEST_CONFIG_PATH)
  end

  test "verify_payments returns json verification status" do
    stripe = StripeConfig.current
    stripe.update!(publishable_key_test: "pk_test_123", secret_key_test: "sk_test_123")

    Stripe::Balance.expects(:retrieve).returns(OpenStruct.new(object: "balance"))

    post admin_verify_payments_config_path

    assert_response :success
    json = JSON.parse(response.body)
    assert json["verified"]
    assert json["verified_at"].present?
    assert_nil json["error"]
  end

  # ── Newsletters (Postmark) ───────────────────────────────────────────────

  test "edit_newsletters renders the integration form" do
    get admin_edit_newsletters_config_path
    assert_response :success
    assert_select "form[action=?]", admin_newsletters_config_path
  end

  test "update_newsletters writes test token to YAML and syncs" do
    patch admin_newsletters_config_path, params: {
      test: { server_token: "test-server-token" }
    }

    assert_redirected_to admin_edit_newsletters_config_path
    assert_equal "Postmark configuration saved", flash[:notice]

    path = File.join(SiteConfig::INTEGRATIONS_PATH, "postmark.yml")
    assert File.exist?(path)
    yaml = YAML.load_file(path)
    assert_equal "test-server-token", yaml["test"]["server_token"]

    postmark = PostmarkConfig.current
    assert_equal "test-server-token", postmark.test_server_token
  end

  test "update_newsletters_live redirects in non-production" do
    patch admin_live_newsletters_config_path, params: {
      live: { server_token: "live-server-token" }
    }

    assert_redirected_to admin_edit_newsletters_config_path
    assert_equal "Live keys are only saved in production.", flash[:notice]
  end

  test "update_newsletters_mode switches mode to live when live token present" do
    postmark = PostmarkConfig.current
    postmark.update!(server_token: "live-token", verified_at: Time.current)

    patch admin_mode_newsletters_config_path, params: { mode: "live" }

    assert_redirected_to admin_edit_newsletters_config_path
    assert_equal "Newsletters mode set to Live", flash[:notice]
    assert postmark.reload.mode_live?
  end

  test "disconnect_newsletters clears all tokens" do
    postmark = PostmarkConfig.current
    postmark.update!(server_token: "test-token", verified_at: Time.current)
    PostmarkConfig.save_test_config("server_token" => "test-token")

    delete admin_disconnect_newsletters_config_path

    assert_redirected_to admin_edit_newsletters_config_path
    assert_equal "Postmark disconnected. All tokens cleared.", flash[:notice]

    postmark.reload
    assert_nil postmark.server_token
    assert_nil postmark.verified_at
    assert_not File.exist?(PostmarkConfig::TEST_CONFIG_PATH)
  end

  test "regenerate_postmark_webhook_token creates new token" do
    postmark = PostmarkConfig.current
    old_token = postmark.webhook_token

    post admin_regenerate_webhook_token_newsletters_config_path

    assert_redirected_to admin_edit_newsletters_config_path
    assert_equal "Webhook token regenerated. Update the URL in Postmark!", flash[:notice]
    assert_not_equal old_token, postmark.reload.webhook_token
  end

  test "verify_newsletters returns json verification status" do
    postmark = PostmarkConfig.current
    postmark.update!(server_token: "test-token")

    PostmarkService.expects(:test_connection).returns({ success: true })

    post admin_verify_newsletters_config_path

    assert_response :success
    json = JSON.parse(response.body)
    assert json["verified"]
    assert json["verified_at"].present?
    assert_nil json["error"]
  end

  # ── Snipcart (Store) ─────────────────────────────────────────────────────

  test "edit_snipcart renders the integration form" do
    get admin_edit_snipcart_integration_config_path
    assert_response :success
    assert_select "form[action=?]", admin_snipcart_integration_config_path
  end

  test "update_snipcart writes test key to YAML and syncs" do
    patch admin_snipcart_integration_config_path, params: {
      test: { api_key: "test-api-key-123" }
    }

    assert_redirected_to admin_edit_snipcart_integration_config_path
    assert_equal "Store (Snipcart) configuration saved", flash[:notice]

    path = File.join(SiteConfig::INTEGRATIONS_PATH, "snipcart.yml")
    assert File.exist?(path)
    yaml = YAML.load_file(path)
    assert_equal "test-api-key-123", yaml["test"]["api_key"]

    snipcart = SnipcartConfig.current
    assert_equal "test-api-key-123", snipcart.api_key_test
  end

  test "update_snipcart_live redirects in non-production" do
    patch admin_live_snipcart_integration_config_path, params: {
      live: { api_key: "live-api-key" }
    }

    assert_redirected_to admin_edit_snipcart_integration_config_path
    assert_equal "Live keys are only saved in production.", flash[:notice]
  end

  test "update_snipcart_mode switches mode to live when live key present" do
    snipcart = SnipcartConfig.current
    snipcart.update!(api_key_live: "live-api-key", verified_at: Time.current)

    patch admin_mode_snipcart_integration_config_path, params: { mode: "live" }

    assert_redirected_to admin_edit_snipcart_integration_config_path
    assert_equal "Store mode set to Live", flash[:notice]
    assert snipcart.reload.mode_live?
  end

  test "disconnect_snipcart clears all keys" do
    snipcart = SnipcartConfig.current
    snipcart.update!(api_key_test: "test-key", api_key_live: "live-key", verified_at: Time.current)
    SnipcartConfig.save_test_config("api_key" => "test-key")

    delete admin_disconnect_snipcart_integration_config_path

    assert_redirected_to admin_edit_snipcart_integration_config_path
    assert_equal "Snipcart disconnected. All keys cleared.", flash[:notice]

    snipcart.reload
    assert_nil snipcart.api_key_test
    assert_nil snipcart.api_key_live
    assert_nil snipcart.verified_at
    assert_not File.exist?(SnipcartConfig::TEST_CONFIG_PATH)
  end

  test "verify_snipcart returns json verification status" do
    snipcart = SnipcartConfig.current
    snipcart.update!(api_key_test: "test-key", verified_at: Time.current)

    SnipcartConfig.any_instance.stubs(:verify!).returns(true)

    post admin_verify_snipcart_integration_config_path

    assert_response :success
    json = JSON.parse(response.body)
    assert json["verified"]
    assert json["verified_at"].present?
    assert_nil json["error"]
  end

  # ── Edge cases ───────────────────────────────────────────────────────────

  test "update_payments_mode rejects invalid mode" do
    patch admin_mode_payments_config_path, params: { mode: "invalid" }

    assert_redirected_to admin_edit_payments_config_path
    assert_equal "Invalid mode: \"invalid\"", flash[:error]
  end

  test "update_newsletters_mode rejects invalid mode" do
    patch admin_mode_newsletters_config_path, params: { mode: "staging" }

    assert_redirected_to admin_edit_newsletters_config_path
    assert_equal "Invalid mode: \"staging\"", flash[:error]
  end

  test "update_snipcart_mode rejects invalid mode" do
    patch admin_mode_snipcart_integration_config_path, params: { mode: "staging" }

    assert_redirected_to admin_edit_snipcart_integration_config_path
    assert_equal "Invalid mode: \"staging\"", flash[:error]
  end

  test "unauthenticated user is redirected from integration pages" do
    # Clear the admin session cookie directly
    cookies.delete("session_id")
    get admin_edit_payments_config_path
    assert_redirected_to new_session_path
  end

  private

  def ensure_feature_file(filename)
    features_path = SiteConfig::FEATURES_PATH
    FileUtils.mkdir_p(features_path)
    path = features_path.join(filename)

    case filename
    when "members.yml"
      File.write(path, <<~YAML)
        payments:
          enabled: true
        newsletter:
          enabled: true
      YAML
    else
      File.write(path, "{}")
    end

    # Sync to SiteConfig so current() reads from the record, not stale cache
    type = "features/#{filename.sub(/\.yml$/, "")}"
    SiteConfig.sync_from_file(type)
    SiteConfig.reload!(type)
  end
end
