# frozen_string_literal: true

require "test_helper"

# The two shapes a paid podcast or release can take, both of which have to work:
#
#   free show + paid episodes  → public feed carries the free ones
#   paid show + free episodes  → public feed carries the free ones
#   paid show, nothing free    → no public feed at all
#
# The second used to be impossible: show-level `audience: paid` 404'd the public
# feed outright, so there was no way to let people sample a paid podcast by
# subscribing. And that 404 was masking a gap — the feed filtered on the post's
# own audience, so an episode inheriting paid would have been listed with an
# audio URL that 403s.
class SamplerFeedTest < ActionDispatch::IntegrationTest
  setup do
    # Teasers off, so "is there a public feed" turns purely on free episodes.
    SiteConfig.stubs(:feature).returns(nil)
    SiteConfig.stubs(:feature).with("members", "everyone.show_paid_content").returns(false)
  end

  teardown do
    path = SiteConfig::FEATURES_PATH.join("podcast.yml")
    File.delete(path) if File.exist?(path)
    SiteConfig.reload!("features/podcast")
  end

  def write_show(audience)
    path = SiteConfig::FEATURES_PATH.join("podcast.yml")
    FileUtils.mkdir_p(File.dirname(path))
    entry = PodcastConfig.default_entry.merge(
      "title" => "Show", "description" => "About things", "audience" => audience
    )
    File.write(path, { "the-show" => entry }.to_yaml.sub(/\A---\s*\n/, ""))
    SiteConfig.sync_from_file("features/podcast")
  end

  def episode(title, audience: nil)
    meta = { "title" => title, "url_name" => title.parameterize, "status" => "published",
             "post_type" => "podcast", "podcast" => "the-show", "date" => "2026-01-01",
             "audio" => "/media/audio/#{title.parameterize}.mp3", "guid" => title.parameterize }
    meta["audience"] = audience if audience
    Post.create!(file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "#{title.parameterize}.md"),
                 content: "Body.", metadata: meta)
  end

  def public_titles
    get "/podcast/the-show.xml"
    return nil unless response.successful?
    Nokogiri::XML(response.body).xpath("//item/title").map(&:text)
  end

  # ── Free show, paid episodes ───────────────────────────────────────────────

  test "a free show's public feed carries only its free episodes" do
    write_show("")
    episode("Free One")
    episode("Paid One", audience: "paid")

    assert_equal [ "Free One" ], public_titles
  end

  # ── Paid show, free episodes: the case that didn't work ────────────────────

  test "a paid show with free openers still has a public feed" do
    write_show("paid")
    episode("Opener", audience: "everyone")
    episode("Members Only")

    assert_equal [ "Opener" ], public_titles,
      "the free opener is the whole point — it's how someone samples a paid show"
  end

  test "a paid show with nothing free has no public feed" do
    write_show("paid")
    episode("One")
    episode("Two")

    get "/podcast/the-show.xml"
    assert_response :not_found
  end

  # The gap the old 404 was hiding: an episode inheriting paid must not be
  # listed publicly with an audio URL that then 403s.
  test "an episode inheriting paid is excluded from the public feed" do
    write_show("paid")
    episode("Opener", audience: "everyone")
    episode("Inherits Paid")

    assert_not_includes public_titles, "Inherits Paid"
  end

  # ── The private feed carries everything ────────────────────────────────────

  def member
    Member.create!(email: "m#{Member.count}@example.com", name: "M", tier: :paid, status: :active)
  end

  test "the private feed carries free and paid alike" do
    write_show("paid")
    episode("Opener", audience: "everyone")
    episode("Members Only")

    get "/podcast/the-show/private.xml", params: { token: member.media_token }

    assert_response :success
    assert_equal %w[Opener Members\ Only].sort,
                 Nokogiri::XML(response.body).xpath("//item/title").map(&:text).sort
  end

  # ── The link has to agree with the feed ────────────────────────────────────
  #
  # The rule lived in three places — the controller that serves the feed and
  # the two views that link to it. Changing the controller alone meant the feed
  # existed and nothing pointed at it: a paid show with free episodes served
  # /podcast/<key>.xml while the page showed no RSS link at all.

  def episode_page(title)
    get "/posts/#{title.parameterize}"
    response.body
  end

  test "a paid show with a free episode links to its public feed" do
    write_show("paid")
    episode("Opener", audience: "everyone")
    episode("Members Only")

    assert PodcastConfig.public_feed?("the-show"), "the feed exists"
    assert_includes episode_page("Opener"), "/podcast/the-show.xml"
  end

  test "a show with nothing free links to no public feed" do
    write_show("paid")
    episode("One")

    assert_not PodcastConfig.public_feed?("the-show")
    assert_not_includes episode_page("One"), "/podcast/the-show.xml"
  end

  test "a free show links to its feed as before" do
    write_show("")
    episode("Open")

    assert_includes episode_page("Open"), "/podcast/the-show.xml"
  end

  # Teasers are public content in their own right, so they keep the feed alive
  # even when every episode is paid.
  test "teasers keep the feed and its link" do
    SiteConfig.stubs(:feature).with("members", "everyone.show_paid_content").returns(true)
    write_show("paid")
    episode("Members Only")

    assert PodcastConfig.public_feed?("the-show")
  end
end
