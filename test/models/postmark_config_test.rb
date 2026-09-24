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

  test "verify_webhooks! stamps verified_at when Postmark reports success" do
    @config.update!(server_token: "srv")
    url = "https://acme.com/webhooks/postmark/tok"
    PostmarkService.expects(:verify_webhooks).with("srv", url).returns({ ok: true, results: [] })
    result = @config.verify_webhooks!(url)
    assert result[:ok]
    assert @config.reload.webhook_verified?
  end

  test "verify_webhooks! clears verified_at when Postmark reports failure" do
    @config.update!(server_token: "srv", webhook_verified_at: Time.current)
    url = "https://acme.com/webhooks/postmark/tok"
    PostmarkService.expects(:verify_webhooks).with("srv", url).returns({ ok: false, error: "nope" })
    @config.verify_webhooks!(url)
    assert_not @config.reload.webhook_verified?
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
