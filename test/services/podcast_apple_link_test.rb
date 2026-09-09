require "test_helper"

class PodcastAppleLinkTest < ActiveSupport::TestCase
  APPLE_URL = "https://podcasts.apple.com/us/podcast/the-briefcase-podcast/id553753672".freeze

  test "extracts the numeric id from an Apple Podcasts URL" do
    assert PodcastAppleLink.apple_url?(APPLE_URL)
    assert_equal "553753672", PodcastAppleLink.podcast_id(APPLE_URL)
  end

  test "ignores non-Apple URLs" do
    assert_not PodcastAppleLink.apple_url?("https://example.com/podcast/feed.xml")
    assert_nil PodcastAppleLink.podcast_id("https://example.com/podcast/feed.xml")
  end

  test "derives Apple + Overcast subscribe links from an id" do
    links = PodcastAppleLink.subscribe_links("553753672")
    assert_equal "https://podcasts.apple.com/podcast/id553753672", links["apple_podcasts"]
    assert_equal "https://overcast.fm/itunes553753672", links["overcast"]
  end

  test "resolves an id to the feed URL via the lookup API" do
    stub = lambda do |url|
      assert_includes url, "id=553753672"
      { "results" => [ { "feedUrl" => "https://feeds.example.com/show.xml" } ] }.to_json
    end
    assert_equal "https://feeds.example.com/show.xml",
                 PodcastAppleLink.feed_url("553753672", fetcher: stub)
  end

  test "feed_url returns nil when the lookup has no results" do
    assert_nil PodcastAppleLink.feed_url("999", fetcher: ->(_u) { { "results" => [] }.to_json })
  end
end
