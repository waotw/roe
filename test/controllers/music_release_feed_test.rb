# frozen_string_literal: true

require "test_helper"

# A release published as a podcast-format feed, so someone can submit an album
# to Apple Podcasts or Spotify without touching the Podcast feature. The tests
# that matter are the ones about validity: a feed a platform rejects is worse
# than no feed, because the failure shows up days later on someone else's
# server.
class MusicReleaseFeedTest < ActionDispatch::IntegrationTest
  def write_music(releases)
    path = SiteConfig::FEATURES_PATH.join("music.yml")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, { "artist" => "Yitta Bitta", "releases" => releases }.to_yaml)
    SiteConfig.sync_from_file("features/music")
  end

  def complete_release(extra = {})
    { "title" => "Summer Release", "synopsis" => "Six tracks.",
      "cover" => "/media/images/summer.jpg", "feed" => true }.merge(extra)
  end

  def track(title, number:, release: "summer", status: "published", extra: {})
    path = File.join(RoeSitePaths::SITE_PATH, "posts", "#{title.parameterize}.md")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "---\ntitle: #{title}\n---\nBody.\n")
    Post.create!(
      file_path: path, content: "Body.",
      metadata: {
        "title" => title, "status" => status, "url_name" => title.parameterize,
        "post_type" => "music", "release" => release, "track_number" => number,
        "audio" => "/media/audio/#{title.parameterize}.mp3", "date" => "2026-06-01",
        "guid" => "guid-#{title.parameterize}"
      }.merge(extra)
    )
  end

  teardown do
    path = SiteConfig::FEATURES_PATH.join("music.yml")
    File.delete(path) if File.exist?(path)
    SiteConfig.reload!("features/music")
  end

  test "a complete release serves a feed" do
    write_music("summer" => complete_release)
    track("Opening", number: "1")

    get "/music/summer.xml"

    assert_response :success
    assert_equal "application/rss+xml", response.media_type
  end

  # Apple validates against a fixed category list, so the release's free-text
  # genre can't be the itunes:category — it would be rejected.
  test "the itunes category is Music, whatever the genre says" do
    write_music("summer" => complete_release("genre" => "Shoegaze"))
    track("Opening", number: "1")

    get "/music/summer.xml"
    feed = Nokogiri::XML(response.body)

    assert_equal "Music", feed.at_xpath("//itunes:category",
      "itunes" => "http://www.itunes.com/dtds/podcast-1.0.dtd")["text"]
  end

  # The genre still travels — as stock RSS <category>, which podcast platforms
  # don't read, plus podcast:medium for apps that can treat it as music.
  test "the genre rides along without touching the itunes category" do
    write_music("summer" => complete_release("genre" => "Shoegaze"))
    track("Opening", number: "1")

    get "/music/summer.xml"
    feed = Nokogiri::XML(response.body)

    assert_equal "Shoegaze", feed.at_xpath("//channel/category")&.text
    assert_equal "music", feed.at_xpath("//podcast:medium",
      "podcast" => "https://podcastindex.org/namespace/1.0")&.text
  end

  # Serial makes a podcatcher play oldest-first, which for a release is the
  # running order. Episodic would start the listener on the last track.
  test "tracks are in running order and the feed is serial" do
    write_music("summer" => complete_release)
    track("Third", number: "3")
    track("First", number: "1")
    track("Second", number: "2")

    get "/music/summer.xml"
    feed = Nokogiri::XML(response.body)

    assert_equal %w[First Second Third], feed.xpath("//item/title").map(&:text)
    assert_equal "serial", feed.at_xpath("//itunes:type",
      "itunes" => "http://www.itunes.com/dtds/podcast-1.0.dtd").text
  end

  test "a track's number becomes its episode number" do
    write_music("summer" => complete_release)
    track("Opening", number: "4")

    get "/music/summer.xml"
    feed = Nokogiri::XML(response.body)

    assert_equal "4", feed.at_xpath("//itunes:episode",
      "itunes" => "http://www.itunes.com/dtds/podcast-1.0.dtd").text
  end

  # Every item needs a stable guid or subscribers see the whole release as new
  # on each refresh. Music tracks used to get none at all.
  test "every item carries a guid" do
    write_music("summer" => complete_release)
    track("Opening", number: "1")
    track("Closing", number: "2")

    get "/music/summer.xml"
    guids = Nokogiri::XML(response.body).xpath("//item/guid").map(&:text)

    assert_equal 2, guids.size
    assert_empty guids.select(&:blank?)
    assert_equal guids.uniq, guids
  end

  test "only published tracks on this release appear" do
    write_music("summer" => complete_release, "winter" => complete_release("title" => "Winter"))
    track("Opening", number: "1")
    track("Draft Track", number: "2", status: "draft")
    track("Other Release", number: "1", release: "winter")

    get "/music/summer.xml"

    assert_equal %w[Opening], Nokogiri::XML(response.body).xpath("//item/title").map(&:text)
  end

  # One flagged track flags the release — Apple asks at the channel level.
  test "the channel is explicit when any track is" do
    write_music("summer" => complete_release)
    track("Clean", number: "1")
    track("Rude", number: "2", extra: { "explicit" => true })

    get "/music/summer.xml"

    assert_equal "true", Nokogiri::XML(response.body).at_xpath("//channel/itunes:explicit",
      "itunes" => "http://www.itunes.com/dtds/podcast-1.0.dtd").text
  end

  # ── When there shouldn't be a feed ─────────────────────────────────────────

  test "an unticked release has no feed" do
    write_music("summer" => complete_release("feed" => false))
    track("Opening", number: "1")

    get "/music/summer.xml"
    assert_response :not_found
  end

  test "a release missing what Apple validates has no feed" do
    MusicConfigSchema::FEED_REQUIRED_KEYS.each do |missing|
      write_music("summer" => complete_release.merge(missing => ""))
      get "/music/summer.xml"
      assert_response :not_found, "a release with no #{missing} should not serve a feed"
    end
  end

  test "a paid release has no public feed" do
    write_music("summer" => complete_release("audience" => "paid"))
    track("Opening", number: "1")

    get "/music/summer.xml"
    assert_response :not_found
  end

  test "an unknown release is a 404, not an empty feed" do
    write_music("summer" => complete_release)

    get "/music/nothing-here.xml"
    assert_response :not_found
  end

  # The Podcast feature and release feeds are separate systems that share a
  # file format. A release must never need, or appear in, podcast.yml.
  test "a release feed works with no podcast config at all" do
    path = SiteConfig::FEATURES_PATH.join("podcast.yml")
    File.delete(path) if File.exist?(path)
    SiteConfig.reload!("features/podcast")

    write_music("summer" => complete_release)
    track("Opening", number: "1")

    get "/music/summer.xml"
    assert_response :success
  end

  # ── The private feed ───────────────────────────────────────────────────────
  #
  # A release with paid tracks needs somewhere to deliver full audio to the
  # people who paid, and a wholly-paid release has no public feed at all. Same
  # arrangement podcasts have had; music had the refusal without the delivery.

  def member(tier: :paid, status: :active)
    Member.create!(email: "m#{Member.count}@example.com", name: "Member #{Member.count}",
                   tier: tier, status: status)
  end

  test "the private feed refuses without a token" do
    write_music("summer" => complete_release)
    track("Opening", number: "1")

    get "/music/summer/private.xml"
    assert_response :unauthorized
  end

  test "a free or cancelled member is refused" do
    write_music("summer" => complete_release)
    track("Opening", number: "1")

    get "/music/summer/private.xml", params: { token: member(tier: :free).media_token }
    assert_response :unauthorized

    get "/music/summer/private.xml", params: { token: member(status: :cancelled).media_token }
    assert_response :unauthorized
  end

  test "an unknown token is refused rather than treated as absent" do
    write_music("summer" => complete_release)

    get "/music/summer/private.xml", params: { token: "not-a-real-token" }
    assert_response :unauthorized
  end

  test "a paid, active member gets the feed" do
    write_music("summer" => complete_release)
    track("Opening", number: "1")

    get "/music/summer/private.xml", params: { token: member.media_token }
    assert_response :success
  end

  # The point of the whole thing: a paid track's audio is in the private feed
  # and not in the public one.
  test "paid tracks carry their audio only in the private feed" do
    write_music("summer" => complete_release)
    track("Free Track", number: "1")
    track("Paid Track", number: "2", extra: { "audience" => "paid" })

    get "/music/summer/private.xml", params: { token: member.media_token }
    private_feed = Nokogiri::XML(response.body)
    assert_equal %w[Free\ Track Paid\ Track], private_feed.xpath("//item/title").map(&:text)
    assert_equal 2, private_feed.xpath("//item/enclosure").size, "both tracks playable"

    get "/music/summer.xml"
    public_feed = Nokogiri::XML(response.body)
    titles = public_feed.xpath("//item/title").map(&:text)
    assert_includes titles, "Free Track"
    assert_equal 1, public_feed.xpath("//item/enclosure").size,
      "the paid track must not be downloadable from the public feed"
  end

  # A wholly-paid release: the public feed is gone, and this is the only copy.
  test "a paid release has no public feed but does have a private one" do
    write_music("summer" => complete_release("audience" => "paid"))
    track("Opening", number: "1")

    get "/music/summer.xml"
    assert_response :not_found

    get "/music/summer/private.xml", params: { token: member.media_token }
    assert_response :success
    assert_equal 1, Nokogiri::XML(response.body).xpath("//item/enclosure").size
  end

  # No feed turned on means no feed to have a private copy of — otherwise the
  # private URL would quietly publish a release the owner never opted in to.
  test "an unticked release has no private feed either" do
    write_music("summer" => complete_release("feed" => false))
    track("Opening", number: "1")

    get "/music/summer/private.xml", params: { token: member.media_token }
    assert_response :not_found
  end

  test "an unknown release is a 404 on the private feed too" do
    write_music("summer" => complete_release)

    get "/music/nothing-here/private.xml", params: { token: member.media_token }
    assert_response :not_found
  end

  # A podcast app fetches an enclosure with no cookies, so a protected file is
  # only reachable if the URL carries its own proof. Without this the private
  # feed would list tracks the app then can't download.
  test "private feed enclosures carry the member's media token" do
    write_music("summer" => complete_release)
    track("Opening", number: "1", extra: { "audience" => "paid" })
    m = member

    get "/music/summer/private.xml", params: { token: m.media_token }
    url = Nokogiri::XML(response.body).at_xpath("//item/enclosure")["url"]

    assert_includes url, "token=#{m.media_token}"
  end

  # The public feed points only at free files, so a token there would be a
  # credential handed to anyone who subscribes.
  test "public feed enclosures carry no token" do
    write_music("summer" => complete_release)
    track("Opening", number: "1")

    get "/music/summer.xml"
    url = Nokogiri::XML(response.body).at_xpath("//item/enclosure")["url"]

    assert_not_includes url, "token="
  end

  # The sign-in token is not a feed key. It was accepted for a while so URLs
  # from before the two-token split kept working; that's gone, because a feed
  # URL travels and this one hands over the account.
  test "the sign-in token does not open a private feed" do
    write_music("summer" => complete_release)
    track("Opening", number: "1")

    get "/music/summer/private.xml", params: { token: member.access_token }
    assert_response :unauthorized
  end
end
