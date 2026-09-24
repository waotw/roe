require "test_helper"

class PostmarkConfigTest < ActiveSupport::TestCase
  setup do
    PostmarkConfig.delete_all
    @config = PostmarkConfig.current
  end

  # ── Webhook status ───────────────────────────────────────────────────────

  test "webhook_configured? is false without a token or URL" do
    assert_not @config.webhook_configured?(nil), "no URL → not configured"
    @config.update!(server_token: nil)
    assert_not @config.webhook_configured?("https://acme.com/webhooks/postmark/x"),
               "no server token → can't check, so not configured"
  end

  test "webhook_configured? delegates to a live API lookup when a token is present" do
    @config.update!(server_token: "srv")
    url = "https://acme.com/webhooks/postmark/tok"
    PostmarkService.expects(:webhook_for_url?).with("srv", url).returns(true)
    assert @config.webhook_configured?(url)
  end

  test "record_webhook_delivery! stamps only the matching probe id" do
    @config.update_columns(webhook_probe_message_id: "probe-123", webhook_verified_at: nil)

    @config.record_webhook_delivery!("some-other-id")
    assert_nil @config.reload.webhook_verified_at, "an unrelated delivery must not verify"

    @config.record_webhook_delivery!("probe-123")
    assert @config.reload.webhook_verified?, "the probe's own delivery verifies the webhook"
  end

  test "record_webhook_delivery! ignores a blank id" do
    @config.update_columns(webhook_probe_message_id: "probe-123")
    @config.record_webhook_delivery!("")
    assert_nil @config.reload.webhook_verified_at
  end

  # ── Account token: kept only in production ───────────────────────────────

  test "store_account_token? is false outside production" do
    assert_not PostmarkConfig.store_account_token?, "dev/test never keeps the account token"
  end

  test "store_account_token? is true in production" do
    with_env("production") { assert PostmarkConfig.store_account_token? }
  end

  test "account token round-trips through encryption when stored" do
    @config.store_account_token!("acct-secret")
    assert @config.account_token_present?
    assert_equal "acct-secret", @config.reload.stored_account_token
    @config.remove_account_token!
    assert_not @config.reload.account_token_present?
  end

  private

  def with_env(name)
    original = Rails.env
    Rails.env = name
    yield
  ensure
    Rails.env = original
  end
end
