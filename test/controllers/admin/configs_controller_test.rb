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

    assert_redirected_to admin_edit_payments_config_path(tab: "test")
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

    assert_redirected_to admin_edit_payments_config_path(tab: "test")

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

    assert_redirected_to admin_edit_payments_config_path(tab: "live")
    assert_equal "Payments mode set to Live", flash[:notice]
    assert stripe.reload.mode_live?
  end

  test "update_payments_mode rejects live without live keys" do
    patch admin_mode_payments_config_path, params: { mode: "live" }

    assert_redirected_to admin_edit_payments_config_path(tab: "test")
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

    assert_redirected_to admin_edit_newsletters_config_path(tab: "test")
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

    assert_redirected_to admin_edit_newsletters_config_path(tab: "live")
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

  test "edit_snipcart renders snippet-only tabs that work locally" do
    get admin_edit_snipcart_integration_config_path

    assert_response :success
    # Tabs renamed, both usable locally (no production gate, no masked inputs).
    assert_select "button[data-tabs-panel=?]", "test", text: /Local\/Test/
    assert_select "button[data-tabs-panel=?]", "live", text: /Live\/Static Site/
    assert_select "textarea[name=?]", "test[snippet]"
    assert_select "textarea[name=?]", "live[snippet]"
    # No leftover secret-key inputs.
    assert_select "input[name=?]", "test[secret_key]", count: 0
    assert_select "input[name=?]", "live[secret_key]", count: 0
  end

  test "update_snipcart writes the test snippet to YAML and syncs" do
    patch admin_snipcart_integration_config_path, params: {
      test: { snippet: "<div>test</div>" }
    }

    assert_redirected_to admin_edit_snipcart_integration_config_path(tab: "test")
    assert_equal "Store (Snipcart) Test configuration saved", flash[:notice]

    path = File.join(SiteConfig::INTEGRATIONS_PATH, "snipcart.yml")
    assert File.exist?(path)
    assert_equal "<div>test</div>", YAML.load_file(path)["test"]["snippet"]
    assert_equal "<div>test</div>", SnipcartConfig.current.snippet_test
  end

  # Snipcart's live snippet is a public key, so — unlike Stripe/Postmark live
  # keys — it saves locally with no production gate. It's what the local store
  # and the static-site build both run on.
  test "update_snipcart_live saves the live snippet locally, no production gate" do
    patch admin_live_snipcart_integration_config_path, params: {
      live: { snippet: "<div>live</div>" }
    }

    assert_redirected_to admin_edit_snipcart_integration_config_path(tab: "live")
    assert_equal "Snipcart Live & Static Site configuration saved", flash[:notice]
    assert_equal "<div>live</div>", SnipcartConfig.current.snippet_live
  end

  # The snippets are public and shown in full, so blanking the field clears it
  # (they don't behave like masked secret fields, where blank = "unchanged").
  test "update_snipcart clears the test snippet when submitted blank" do
    SnipcartConfig.save_test_config("snippet" => "<div>old</div>")

    patch admin_snipcart_integration_config_path, params: { test: { snippet: "" } }

    assert_redirected_to admin_edit_snipcart_integration_config_path(tab: "test")
    assert SnipcartConfig.current.snippet_test.blank?, "test snippet cleared"
  end

  test "update_snipcart_live clears the live snippet when submitted blank" do
    SnipcartConfig.save_live_snippet("<div>old</div>")

    patch admin_live_snipcart_integration_config_path, params: { live: { snippet: "" } }

    assert_redirected_to admin_edit_snipcart_integration_config_path(tab: "live")
    assert SnipcartConfig.current.snippet_live.blank?, "live snippet cleared"
  end

  test "update_snipcart_mode switches to live once the live snippet is present" do
    SnipcartConfig.save_live_snippet("<div>live</div>")

    patch admin_mode_snipcart_integration_config_path, params: { mode: "live" }

    assert_redirected_to admin_edit_snipcart_integration_config_path(tab: "live")
    assert_equal "Store mode set to Live", flash[:notice]
    assert SnipcartConfig.current.mode_live?
  end

  test "disconnect_snipcart clears the snippets and verification" do
    SnipcartConfig.save_live_snippet("<div>live</div>")
    SnipcartConfig.save_test_config("snippet" => "<div>test</div>")
    SnipcartConfig.current.update!(verified_at: Time.current)

    delete admin_disconnect_snipcart_integration_config_path

    assert_redirected_to admin_edit_snipcart_integration_config_path
    assert_equal "Snipcart disconnected. All keys cleared.", flash[:notice]

    assert_nil SnipcartConfig.current.verified_at
    assert_not File.exist?(SnipcartConfig::TEST_CONFIG_PATH)
  end

  test "verify_snipcart returns json verification status" do
    SnipcartConfig.current.update!(verified_at: Time.current)
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

    assert_redirected_to admin_edit_payments_config_path(tab: "test")
    assert_equal "Invalid mode: \"invalid\"", flash[:error]
  end

  test "update_newsletters_mode rejects invalid mode" do
    patch admin_mode_newsletters_config_path, params: { mode: "staging" }

    assert_redirected_to admin_edit_newsletters_config_path(tab: "test")
    assert_equal "Invalid mode: \"staging\"", flash[:error]
  end

  test "update_snipcart_mode rejects invalid mode" do
    patch admin_mode_snipcart_integration_config_path, params: { mode: "staging" }

    assert_redirected_to admin_edit_snipcart_integration_config_path(tab: "test")
    assert_equal "Invalid mode: \"staging\"", flash[:error]
  end

  test "unauthenticated user is redirected from integration pages" do
    # Clear the admin session cookie directly
    cookies.delete("session_id")
    get admin_edit_payments_config_path
    assert_redirected_to new_session_path
  end

  test "site config editor renders the nightly-updates toggle" do
    FileUtils.mkdir_p(File.dirname(SiteConfig::SITE_FILE))
    File.write(SiteConfig::SITE_FILE,
               { "title" => "T", "update_channel" => "nightly" }.to_yaml)

    get admin_edit_site_config_path

    assert_response :success
    # Nightly toggle maps to stable/nightly instead of true/false
    assert_select "input[data-config-field=?][data-on-value=?][data-off-value=?]",
                  "update_channel", "nightly", "stable"
  end

  test "content config editor renders the search toggle" do
    FileUtils.mkdir_p(File.dirname(SiteConfig::CONTENT_FILE))
    File.write(SiteConfig::CONTENT_FILE,
               { "search" => { "all_pages" => true } }.to_yaml)

    get admin_edit_content_config_path

    assert_response :success
    # Search moved out of site.yml into content.yml (nested under `search`).
    assert_select "input[data-config-field=?][type=checkbox]", "search.all_pages"
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
