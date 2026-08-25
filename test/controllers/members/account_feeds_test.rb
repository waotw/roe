# frozen_string_literal: true

require "test_helper"

# The account page is where a member looks for their own things. Their private
# feed addresses were only reachable from an episode page, which is the wrong
# place when you've dropped the feed from your podcast app and want it back.
class Members::AccountFeedsTest < ActionDispatch::IntegrationTest
  teardown do
    path = SiteConfig::FEATURES_PATH.join("podcast.yml")
    File.delete(path) if File.exist?(path)
    SiteConfig.reload!("features/podcast")
  end

  def paid_show_with_episode
    path = SiteConfig::FEATURES_PATH.join("podcast.yml")
    FileUtils.mkdir_p(File.dirname(path))
    entry = PodcastConfig.default_entry.merge("title" => "The Show", "audience" => "paid")
    File.write(path, { "the-show" => entry }.to_yaml.sub(/\A---\s*\n/, ""))
    SiteConfig.sync_from_file("features/podcast")

    Post.create!(file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "ep.md"), content: "Body.",
      metadata: { "title" => "Ep", "url_name" => "ep", "status" => "published",
                  "post_type" => "podcast", "podcast" => "the-show", "date" => "2026-01-01",
                  "audio" => "/media/audio/ep.mp3" })
  end

  def sign_in_member(member)
    get "/signin/#{member.access_token}"
  end

  test "a paid member sees their feed URL" do
    paid_show_with_episode
    m = Member.create!(email: "p@example.com", name: "P", tier: :paid, status: :active)
    sign_in_member(m)

    get account_path

    assert_response :success
    assert_select "input.private-feed-url[value*=?]", "/podcast/the-show/private.xml"
    assert_select "input.private-feed-url[value*=?]", m.media_token
  end

  # The token means nothing without a feed address, and showing it on its own
  # invites pasting it somewhere it doesn't belong.
  test "the bare token is never printed" do
    paid_show_with_episode
    m = Member.create!(email: "p2@example.com", name: "P", tier: :paid, status: :active)
    sign_in_member(m)

    get account_path

    urls = css_select("input.private-feed-url").map { |el| el["value"] }
    assert urls.any? { |u| u.include?(m.media_token) }, "the token rides in the URL"

    stripped = response.body.gsub(/value="[^"]*"/, "")
    assert_not_includes stripped, m.media_token, "and appears nowhere else on the page"
    assert_not_includes response.body, m.access_token, "the sign-in token never appears at all"
  end

  test "a free member sees no feeds" do
    paid_show_with_episode
    sign_in_member(Member.create!(email: "f@example.com", name: "F", tier: :free, status: :active))

    get account_path

    assert_response :success
    assert_select "input.private-feed-url", count: 0
  end

  test "no paid content means no feeds block" do
    sign_in_member(Member.create!(email: "p3@example.com", name: "P", tier: :paid, status: :active))

    get account_path

    assert_response :success
    assert_select ".private-feeds", count: 0
  end

  # ── Regenerating ───────────────────────────────────────────────────────────
  #
  # These URLs travel — into podcast apps, shared links, screenshots. Being
  # able to rotate them without touching the sign-in token is the reason the
  # two tokens are separate in the first place.

  test "regenerating issues a new token and leaves the sign-in token alone" do
    paid_show_with_episode
    m = Member.create!(email: "r@example.com", name: "R", tier: :paid, status: :active)
    sign_in_member(m)
    old_media, old_access = m.media_token, m.access_token

    post regenerate_media_token_path

    assert_redirected_to account_path
    m.reload
    assert_not_equal old_media, m.media_token, "a new feed token"
    assert_equal old_access, m.access_token, "signing in is unaffected"
  end

  test "the old URL stops working immediately" do
    paid_show_with_episode
    m = Member.create!(email: "r2@example.com", name: "R", tier: :paid, status: :active)
    old_media = m.media_token

    get "/podcast/the-show/private.xml", params: { token: old_media }
    assert_response :success

    sign_in_member(m)
    post regenerate_media_token_path

    get "/podcast/the-show/private.xml", params: { token: old_media }
    assert_response :unauthorized, "the shared link is dead"

    get "/podcast/the-show/private.xml", params: { token: m.reload.media_token }
    assert_response :success, "and the new one works"
  end

  test "the page offers the button only when there are feeds" do
    m = Member.create!(email: "r3@example.com", name: "R", tier: :paid, status: :active)
    sign_in_member(m)

    get account_path
    assert_select "form[action=?]", regenerate_media_token_path, count: 0

    paid_show_with_episode
    get account_path
    assert_select "form[action=?]", regenerate_media_token_path, count: 1
  end

  test "signing out is required to reach it" do
    post regenerate_media_token_path

    assert_response :redirect
    assert_not_equal account_path, response.location
  end
end
