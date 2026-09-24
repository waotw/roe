require "test_helper"

# The Postmark account-API setup flow: preview (list servers + signatures) and
# run (create/reuse servers, store tokens per env, ensure webhook). The service
# is stubbed — these assert the CONTROLLER's contract: what it stores, and the
# environment split (prod keeps the account token + live token; local discards
# both and only seeds the sandbox).
class PostmarkAccountSetupFlowTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    PostmarkConfig.delete_all
    @pm = PostmarkConfig.current
  end

  teardown { PostmarkConfig.delete_all }

  # Canned Server structs the stubbed service hands back.
  def server(kind:, token:, created: true)
    PostmarkAccountSetup::Server.new(
      id: 1, name: "Acme - #{kind}", token: token,
      delivery_type: kind.to_s.capitalize, created: created
    )
  end

  test "the setup panel renders on the newsletters page" do
    get admin_edit_newsletters_config_path
    assert_response :success
    assert_select "[data-controller~='postmark-setup']"
  end

  test "preview returns reusable servers and signatures as JSON" do
    PostmarkAccountSetup.any_instance.stubs(:list_servers).returns([
      { id: 1, name: "My First Server", delivery_type: "Live", default: true },
      { id: 2, name: "Acme - Production", delivery_type: "Live", default: false }
    ])
    PostmarkAccountSetup.any_instance.stubs(:sender_signatures).returns([
      { email: "a@acme.com", name: "A", domain: "acme.com", confirmed: true }
    ])

    post admin_postmark_account_setup_preview_config_path,
         params: { account_token: "acct" }, as: :json

    body = JSON.parse(response.body)
    assert body["ok"]
    assert_equal 1, body["reusable"].size, "the default server is filtered out"
    assert_equal "Acme - Production", body["reusable"].first["name"]
    assert_equal 1, body["signatures"].size
  end

  test "preview reports a bad token without creating anything" do
    PostmarkAccountSetup.any_instance.stubs(:list_servers)
                        .raises(PostmarkAccountSetup::Error.new("Invalid account token"))
    post admin_postmark_account_setup_preview_config_path,
         params: { account_token: "bad" }, as: :json
    body = JSON.parse(response.body)
    assert_not body["ok"]
    assert_match(/invalid/i, body["error"])
  end

  test "run in production stores the live token AND keeps the account token" do
    Rails.env.stubs(:production?).returns(true)
    PostmarkAccountSetup.any_instance.stubs(:ensure_server)
      .returns(server(kind: :sandbox, token: "sbx"), server(kind: :live, token: "live-tok"))
    PostmarkAccountSetup.any_instance.stubs(:ensure_webhook)
      .returns({ ok: true, streams: { "outbound" => { ok: true, id: 1 }, "broadcast" => { ok: true, id: 2 } } })
    PostmarkService.stubs(:test_connection).returns({ success: true, server: { "DeliveryType" => "Live" } })

    post admin_postmark_account_setup_config_path, params: { account_token: "acct-secret" }

    pm = PostmarkConfig.current
    assert_equal "live-tok", pm.live_server_token, "live server token stored in the DB"
    assert pm.mode_live?, "production switches the config to live mode so the live token is actually used"
    assert pm.account_token_present?, "production keeps the account token"
    assert_equal "acct-secret", pm.stored_account_token
  end

  test "run does not send any verification email (setup only registers)" do
    Rails.env.stubs(:production?).returns(true)
    PostmarkAccountSetup.any_instance.stubs(:ensure_server)
      .returns(server(kind: :sandbox, token: "sbx"), server(kind: :live, token: "live-tok"))
    PostmarkAccountSetup.any_instance.stubs(:ensure_webhook)
      .returns({ ok: true, streams: { "outbound" => { ok: true, id: 1 }, "broadcast" => { ok: true, id: 2 } } })
    PostmarkService.stubs(:test_connection).returns({ success: true })
    # Setup registers the webhook; the round-trip test is a separate, on-demand
    # action — so no email is sent here.
    PostmarkService.expects(:send_transactional_email).never

    post admin_postmark_account_setup_config_path, params: { account_token: "acct-secret" }
    assert_response :redirect
  end

  test "send_test_event fires the probe on demand" do
    PostmarkConfig.any_instance.expects(:verify_webhook!).with(to: User.take.email_address)
                  .returns({ success: true, message_id: "probe" })
    post admin_postmark_send_test_event_config_path
    assert_response :redirect
    assert_match(/test event/i, flash[:notice])
  end

  test "send_test_event surfaces a send failure" do
    PostmarkConfig.any_instance.stubs(:verify_webhook!).returns({ success: false, error: "no sender" })
    post admin_postmark_send_test_event_config_path
    assert_match(/couldn't|no sender/i, flash[:alert].to_s + flash[:notice].to_s)
  end

  test "webhook_status reports verification state" do
    @pm.update_columns(webhook_probe_message_id: "p", webhook_verified_at: Time.current)
    get admin_postmark_webhook_status_config_path, as: :json
    assert JSON.parse(response.body)["verified"]
  end

  test "run locally seeds the sandbox but never stores the account or live token" do
    Rails.env.stubs(:production?).returns(false)
    PostmarkAccountSetup.any_instance.stubs(:ensure_server)
      .returns(server(kind: :sandbox, token: "sbx-local"), server(kind: :live, token: "live-should-not-store"))
    PostmarkAccountSetup.any_instance.stubs(:ensure_webhook).returns({ ok: false, error: "no url" })

    post admin_postmark_account_setup_config_path, params: { account_token: "acct-secret" }

    pm = PostmarkConfig.current
    assert_not pm.account_token_present?, "local must not keep the account token"
    assert_nil pm.live_server_token, "local must not store the live token"
    # Sandbox token landed in the plaintext test file.
    assert_equal "sbx-local", PostmarkConfig.test_config["server_token"]
  end

  test "removing the account token clears it" do
    @pm.store_account_token!("acct")
    delete admin_remove_postmark_account_token_config_path
    assert_not PostmarkConfig.current.account_token_present?
  end
end
