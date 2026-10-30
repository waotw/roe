# frozen_string_literal: true

require "test_helper"

# RedirectManager writes 301 rules into site/system/global/redirects.yml (the
# file SiteRedirectsMiddleware serves). These tests exercise the add/flatten/
# idempotency/normalization logic against the real file, backing it up and
# restoring it like SiteRedirectsTest does.
class RedirectManagerTest < ActiveSupport::TestCase
  setup do
    @path = RedirectManager::CONFIG_PATH
    @original = File.exist?(@path) ? File.read(@path) : nil
    FileUtils.mkdir_p(File.dirname(@path))
    # Start each test from an empty redirect set.
    File.write(@path, "redirects: {}\n")
    SiteRedirectsMiddleware.reload!
  end

  teardown do
    @original ? File.write(@path, @original) : FileUtils.rm_f(@path)
    SiteRedirectsMiddleware.reload!
  end

  def rules = RedirectManager.rules

  test "adds a 301 in the explicit hash form" do
    result = RedirectManager.add_301(from: "/posts/foo", to: "/posts/bar")

    assert result.written
    assert_equal "/posts/foo", result.from
    assert_equal "/posts/bar", result.to
    assert_equal 0, result.flattened
    assert_equal({ "to" => "/posts/bar", "status" => 301 }, rules["/posts/foo"])
  end

  test "flattens a chain so every old path lands on the newest in one hop" do
    RedirectManager.add_301(from: "/posts/foo", to: "/posts/bar")
    result = RedirectManager.add_301(from: "/posts/bar", to: "/posts/baz")

    assert_equal 1, result.flattened
    # foo was pointing at bar; bar now points at baz; foo must be repointed to baz.
    assert_equal "/posts/baz", rules["/posts/foo"]["to"]
    assert_equal "/posts/baz", rules["/posts/bar"]["to"]
  end

  test "is idempotent — re-adding an identical rule reports not written" do
    RedirectManager.add_301(from: "/posts/foo", to: "/posts/bar")
    result = RedirectManager.add_301(from: "/posts/foo", to: "/posts/bar")

    assert_not result.written
    assert_equal 1, rules.size
  end

  test "no-op when from and to are the same path" do
    result = RedirectManager.add_301(from: "/posts/foo", to: "/posts/foo")

    assert_not result.written
    assert_empty rules
  end

  test "no-op when from or to is blank" do
    assert_not RedirectManager.add_301(from: "", to: "/posts/bar").written
    assert_not RedirectManager.add_301(from: "/posts/foo", to: "").written
    assert_empty rules
  end

  test "never writes a self-referential rule when a slug is renamed back" do
    RedirectManager.add_301(from: "/posts/foo", to: "/posts/bar")
    RedirectManager.add_301(from: "/posts/bar", to: "/posts/baz")
    # Rename all the way back to foo.
    RedirectManager.add_301(from: "/posts/baz", to: "/posts/foo")

    # foo -> foo must NOT exist (the middleware would ignore it, but we don't
    # even write it); the earlier aliases now point at foo.
    assert_nil rules["/posts/foo"]
    assert_equal "/posts/foo", rules["/posts/bar"]["to"]
    assert_equal "/posts/foo", rules["/posts/baz"]["to"]
  end

  test "normalizes paths — adds a leading slash and strips a trailing one" do
    RedirectManager.add_301(from: "posts/aaa/", to: "posts/bbb")

    assert_equal({ "to" => "/posts/bbb", "status" => 301 }, rules["/posts/aaa"])
  end

  test "leaves an off-site absolute target untouched" do
    RedirectManager.add_301(from: "/old", to: "https://example.com/new")

    assert_equal "https://example.com/new", rules["/old"]["to"]
  end

  test "preserves existing unrelated rules" do
    File.write(@path, <<~YAML)
      redirects:
        "/roe.git/*":
          to: "https://codeberg.org/waotw/roe"
          status: 301
    YAML
    SiteRedirectsMiddleware.reload!

    RedirectManager.add_301(from: "/posts/foo", to: "/posts/bar")

    assert_equal "https://codeberg.org/waotw/roe", rules["/roe.git/*"]["to"]
    assert_equal "/posts/bar", rules["/posts/foo"]["to"]
  end

  test "the written rule is live in the middleware immediately" do
    RedirectManager.add_301(from: "/posts/foo", to: "/posts/bar")

    rule = SiteRedirectsMiddleware.rules.find { |r| r[:exact] == "/posts/foo" }
    assert rule, "expected the middleware to see the new rule after reload"
    assert_equal "/posts/bar", rule[:to]
    assert_equal 301, rule[:status]
  end
end
