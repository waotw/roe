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

  test "not connected reads as a todo, no webhook row until set up" do
    items = PostmarkStatus.for(@pm)
    assert_equal :todo, item(items, :connection).state
    # Locally, before setup, there's nothing to say about the webhook — the
    # connection row already covers "not connected".
    assert_nil item(items, :webhook)
  end

  test "local, once set up, shows webhooks as informational (never a todo)" do
    @pm.update!(server_token: "sbx")
    PostmarkService.stubs(:test_connection).returns({ success: true })

    row = item(PostmarkStatus.for(@pm), :webhook)
    assert_equal :info, row.state, "local webhooks are informational — they activate on the live site"
    assert_match(/live site/i, row.detail)
  end

  test "production: verified webhooks read green" do
    Rails.env.stubs(:production?).returns(true)
    Rails.env.stubs(:test?).returns(false) # take the production webhook-URL branch
    SiteConfig.stubs(:site_url).returns("https://acme.com")
    @pm.update!(server_token: "srv", verified_at: Time.current, webhook_verified_at: Time.current)
    PostmarkService.stubs(:test_connection).returns({ success: true })

    row = item(PostmarkStatus.for(@pm), :webhook)
    assert_equal :ok, row.state
    assert_match(/verified/i, row.label)
  end

  test "production: registered but unverified reads as a todo pointing at RE-CHECK" do
    Rails.env.stubs(:production?).returns(true)
    Rails.env.stubs(:test?).returns(false)
    SiteConfig.stubs(:site_url).returns("https://acme.com")
    @pm.update!(server_token: "srv", verified_at: Time.current)
    PostmarkService.stubs(:test_connection).returns({ success: true })
    PostmarkConfig.any_instance.stubs(:webhook_configured?).returns(true)

    row = item(PostmarkStatus.for(@pm), :webhook)
    assert_equal :todo, row.state
    assert_match(/re-check/i, row.detail)
  end

  test "production shows a todo when the webhook isn't registered" do
    Rails.env.stubs(:production?).returns(true)
    Rails.env.stubs(:test?).returns(false)
    SiteConfig.stubs(:site_url).returns("https://acme.com")
    @pm.update!(server_token: "srv", verified_at: Time.current)
    PostmarkService.stubs(:test_connection).returns({ success: true })
    PostmarkConfig.any_instance.stubs(:webhook_configured?).returns(false)

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
