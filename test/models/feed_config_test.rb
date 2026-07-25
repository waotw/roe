require "test_helper"

class FeedConfigTest < ActiveSupport::TestCase
  def stub_feeds(hash)
    SiteConfig.stubs(:current).with("features/feeds").returns(stub(config: hash))
  end

  test "feed_names lists configured feeds and drops reserved names" do
    stub_feeds({ "articles" => {}, "music" => {}, "atom" => {} })
    assert_equal %w[articles music], FeedConfig.feed_names
  end

  test "get returns the entry, nil for missing or reserved names" do
    stub_feeds({ "articles" => { "source" => "posts" } })
    assert_equal({ "source" => "posts" }, FeedConfig.get("articles"))
    assert_nil FeedConfig.get("missing")
    assert_nil FeedConfig.get("rss"), "reserved name is never a feed"
  end

  test "paid? reflects the audience field" do
    stub_feeds({ "members" => { "audience" => "paid" }, "public" => { "audience" => "free" }, "bare" => {} })
    assert FeedConfig.paid?("members")
    assert_not FeedConfig.paid?("public")
    assert_not FeedConfig.paid?("bare"), "no audience defaults to free"
  end

  test "an absent feeds.yml means no feeds, not an error" do
    SiteConfig.stubs(:current).with("features/feeds").returns(nil)
    assert_equal({}, FeedConfig.all_feeds)
    assert_empty FeedConfig.feed_names
  end
end
