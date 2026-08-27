# frozen_string_literal: true

require "test_helper"

# Subscribe links that behave the same everywhere don't work everywhere:
# Overcast's web page can't subscribe a visitor to anything, Apple Podcasts has
# no Android app, and a feed URL tapped on a phone opens a wall of XML when
# what you wanted was it on your clipboard.
#
# The markup carries where each link belongs; subscribe_links_controller.js
# hides the rest and turns feed links into copy actions on mobile.
class SubscribeLinksTest < ActionDispatch::IntegrationTest
  setup { SiteFeature.stubs(:members_enabled?).returns(true) }

  teardown do
    path = SiteConfig::FEATURES_PATH.join("podcast.yml")
    File.delete(path) if File.exist?(path)
    SiteConfig.reload!("features/podcast")
  end

  def show_with_links(audience: "everyone")
    path = SiteConfig::FEATURES_PATH.join("podcast.yml")
    FileUtils.mkdir_p(File.dirname(path))
    entry = PodcastConfig.default_entry.merge(
      "title" => "The Show", "audience" => audience,
      "apple_podcasts" => "https://podcasts.apple.com/podcast/id1",
      "overcast" => "https://overcast.fm/itunes1",
      "spotify" => "https://open.spotify.com/show/1"
    )
    File.write(path, { "the-show" => entry }.to_yaml.sub(/\A---\s*\n/, ""))
    SiteConfig.sync_from_file("features/podcast")

    Post.create!(file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "sl-ep.md"),
      content: "Body.",
      metadata: { "title" => "Ep", "url_name" => "sl-ep", "status" => "published",
                  "post_type" => "podcast", "podcast" => "the-show",
                  "date" => "2026-01-01", "audio" => "/media/audio/ep.mp3" })
  end

  def subscribe_block
    response.body[/<div class="subscribe-links".*?<\/div>/m].to_s
  end

  test "Overcast is iOS only — its web page can't subscribe anyone" do
    show_with_links
    get "/posts/sl-ep"

    assert_match(/Overcast<\/a>/, subscribe_block)
    overcast = subscribe_block[/<a[^>]*overcast\.fm[^>]*>/m]
    assert_match(/data-platforms="ios"/, overcast)
  end

  # No Android app; podcasts.apple.com there is a browser page offering nothing.
  test "Apple Podcasts is desktop and iOS, not Android" do
    show_with_links
    get "/posts/sl-ep"

    apple = subscribe_block[/<a[^>]*podcasts\.apple\.com[^>]*>/m]
    assert_equal "desktop ios", apple[/data-platforms="([^"]*)"/, 1]
  end

  # Spotify opens its native app on both phones and works in a browser, so it
  # carries no restriction at all.
  test "Spotify is unmarked, meaning everywhere" do
    show_with_links
    get "/posts/sl-ep"

    spotify = subscribe_block[/<a[^>]*open\.spotify\.com[^>]*>/m]
    assert_no_match(/data-platforms/, spotify)
  end

  test "the feed link becomes a copy action on mobile" do
    show_with_links
    get "/posts/sl-ep"

    rss = subscribe_block[/<a[^>]*the-show\.xml[^>]*>/m]
    assert_match(/data-copy-on-mobile/, rss)
    assert_match(/href="\/podcast\/the-show\.xml"/, rss,
      "and stays a real link, which is what desktop and no-JS both get")
  end

  test "the block is wired to the controller" do
    show_with_links
    get "/posts/sl-ep"

    assert_match(/data-controller="subscribe-links"/, subscribe_block)
  end

  # ── Private feed deep links ──────────────────────────────────────────────

  test "a paid member gets one-tap add buttons, iOS only" do
    show_with_links(audience: "paid")
    m = Member.create!(email: "sl@example.com", name: "SL", tier: :paid, status: :active)
    get "/signin/#{m.access_token}"
    get "/posts/sl-ep"

    assert_match(/href="podcast:\/\/[^"]*private\.xml[^"]*token=/, subscribe_block)
    assert_match(/href="overcast:\/\/x-callback-url\/add\?url=/, subscribe_block)

    apple_add = subscribe_block[/<a[^>]*href="podcast:\/\/[^>]*>/m]
    assert_match(/data-platforms="ios"/, apple_add)
    assert_match(/hidden/, apple_add,
      "hidden until the controller confirms iOS — a scheme with no handler does nothing")
  end

  # A deep link that silently does nothing is worse than no button, so copy
  # stays available beside it.
  test "the copy-able feed link is still there alongside" do
    show_with_links(audience: "paid")
    m = Member.create!(email: "sl2@example.com", name: "SL", tier: :paid, status: :active)
    get "/signin/#{m.access_token}"
    get "/posts/sl-ep"

    assert_match(/data-copy-on-mobile/, subscribe_block)
  end

  test "a signed-out visitor gets no private links at all" do
    show_with_links(audience: "paid")
    get "/posts/sl-ep"

    assert_no_match(/podcast:\/\//, subscribe_block)
    assert_no_match(/overcast:\/\/x-callback-url/, subscribe_block)
  end
end
