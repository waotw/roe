require "test_helper"

# PostmarkStatus turns what Roe knows (plus, in production, a live signature
# read) into the settings-page checklist. These assert the state each row
# reports, and that the live read is only attempted when an account token is
# stored — so local never makes the call.
class PostmarkStatusTest < ActiveSupport::TestCase
  setup do
    PostmarkConfig.delete_all
    @pm = PostmarkConfig.current
    # Default everything to nil, then override the one key we need — the
    # specific-argument stub must come AFTER the catch-all so it wins.
    SiteConfig.stubs(:get).returns(nil)
    SiteConfig.stubs(:get).with("author_email").returns("me@acme.com")
  end

  def item(items, key) = items.find { |i| i.key == key }

  test "not connected reads as a todo" do
    items = PostmarkStatus.for(@pm)
    assert_equal :todo, item(items, :connection).state
    # In the test env (no dev tunnel host) the webhook can't be reached, so it's
    # informational rather than an actionable todo — see the reachability tests.
    assert_equal :info, item(items, :webhook).state
  end

  test "a connected, webhook-verified config reads green" do
    @pm.update!(server_token: "srv", verified_at: Time.current)
    @pm.update_columns(webhook_probe_message_id: "p", webhook_verified_at: Time.current)
    PostmarkService.stubs(:test_connection).returns({ success: true })

    items = PostmarkStatus.for(@pm)
    assert_equal :ok, item(items, :connection).state
    assert_equal :ok, item(items, :webhook).state
  end

  test "webhook row is informational (not a todo) on local without a tunnel host" do
    # No dev_host / public allowed_hosts → webhook_url is nil locally.
    SiteConfig.stubs(:development).returns(nil)
    row = item(PostmarkStatus.for(@pm), :webhook)
    assert_equal :info, row.state, "local can't create webhooks, so it's not an actionable todo"
    assert_match(/live site|dev_host/i, row.detail)
  end

  test "webhook row is a todo when reachable but not yet set up (production-like)" do
    SiteConfig.stubs(:development).with("dev_host").returns("acme.ngrok.app")
    SiteConfig.stubs(:development).with("allowed_hosts").returns([])
    Rails.env.stubs(:development?).returns(true)
    row = item(PostmarkStatus.for(@pm), :webhook)
    assert_equal :todo, row.state
  end

  test "missing sender address is a warning" do
    SiteConfig.unstub(:get)
    SiteConfig.stubs(:get).returns(nil)
    items = PostmarkStatus.for(@pm)
    assert_equal :warn, item(items, :sender).state
  end

  test "no live read happens without a stored account token (local)" do
    # store_account_token? is false outside production, so stored_account_token
    # is nil and the DKIM/return-path rows are absent — not fetched.
    PostmarkAccountSetup.any_instance.expects(:sender_detail).never
    items = PostmarkStatus.for(@pm)
    assert_nil item(items, :dkim), "DKIM row only appears from a live read"
  end

  test "a stored account token drives DKIM and return-path rows" do
    Rails.env.stubs(:production?).returns(true)
    @pm.store_account_token!("acct")
    PostmarkAccountSetup.any_instance.stubs(:sender_detail).returns(
      { email: "me@acme.com", confirmed: true, dkim_verified: false, return_path_verified: true }
    )

    items = PostmarkStatus.for(@pm)
    assert_equal :ok,   item(items, :sender).state,       "confirmed sender is green"
    assert_equal :todo, item(items, :dkim).state,         "unverified DKIM is a todo"
    assert_equal :ok,   item(items, :return_path).state
  end
end
