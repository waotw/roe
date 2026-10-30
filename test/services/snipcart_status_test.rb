require "test_helper"

# SnipcartStatus checklist — Snipcart has no management API, so the honest
# signals are environment-split: local shows connection + mode + a "completes on
# your live site" note; production adds webhook-received and domain-match rows.
class SnipcartStatusTest < ActiveSupport::TestCase
  setup do
    SnipcartOrder.delete_all
    @sc = SnipcartConfig.current
    @sc.update!(mode: :test)
  end

  def item(items, key) = items.find { |i| i.key == key }

  # ── Local (development) ─────────────────────────────────────────────────────

  test "local shows connection, mode, and an orders-complete-on-live note" do
    @sc.stubs(:current_snippet).returns("<div>snippet</div>")
    @sc.stubs(:verified_at).returns(Time.current)

    items = SnipcartStatus.for(@sc, ui_production: false)
    assert_equal :ok, item(items, :connection).state
    assert item(items, :local), "has the live-only note"
    # no live-config rows locally
    assert_nil item(items, :webhook)
    assert_nil item(items, :domain)
  end

  # ── Production ──────────────────────────────────────────────────────────────

  test "not connected when no snippet is present" do
    @sc.stubs(:current_snippet).returns("")
    items = SnipcartStatus.for(@sc, ui_production: true)
    assert_equal :todo, item(items, :connection).state
    assert_nil item(items, :webhook) # omitted until connected
  end

  test "connected shows a green connection and mode row" do
    @sc.stubs(:current_snippet).returns("<div>snippet</div>")
    @sc.stubs(:verified_at).returns(Time.current)
    items = SnipcartStatus.for(@sc, ui_production: true)
    assert_equal :ok, item(items, :connection).state
    assert_equal :ok, item(items, :mode).state
  end

  test "webhook row is a todo until an order is received, then ok" do
    @sc.stubs(:current_snippet).returns("<div>snippet</div>")
    SiteConfig.stubs(:site_url).returns("https://shop.example.com")
    # snipcart_webhook_url needs a resolvable host in test env (no inferred host).
    SiteConfig.stubs(:development).returns(nil)
    SiteConfig.stubs(:development).with("dev_host").returns("shop.example.com")

    # No orders yet, but a public URL exists → todo to paste the URL.
    assert_equal :todo, item(SnipcartStatus.for(@sc, ui_production: true), :webhook).state

    # An order arrived in this mode → proof the webhook works.
    SnipcartOrder.record_completed!({ "token" => "t1", "email" => "a@b.com", "finalGrandTotal" => 5.0, "currency" => "usd" }, mode: "test")
    assert_equal :ok, item(SnipcartStatus.for(@sc, ui_production: true), :webhook).state
  end

  test "domain row warns on a mismatch and passes on a match" do
    @sc.stubs(:current_snippet).returns("<div>snippet</div>")
    @sc.stubs(:default_domain).returns("shop.example.com")

    SiteConfig.stubs(:site_url).returns("https://shop.example.com")
    assert_equal :ok, item(SnipcartStatus.for(@sc, ui_production: true), :domain).state

    SiteConfig.stubs(:site_url).returns("https://different.example.com")
    assert_equal :warn, item(SnipcartStatus.for(@sc, ui_production: true), :domain).state
  end
end
