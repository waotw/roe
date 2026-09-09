# frozen_string_literal: true

require "test_helper"

# A member could only find their private feed URL by first landing on an
# episode page — a poor place to look when you've dropped the feed from your
# podcast app and want it back. These are the URLs the account page lists.
class PrivateFeedsTest < ActiveSupport::TestCase
  # Everything here is downstream of the members system being on — with it off
  # there are no members, so there's nothing to list.
  setup { SiteFeature.stubs(:members_enabled?).returns(true) }

  teardown do
    %w[podcast music feeds].each do |f|
      path = SiteConfig::FEATURES_PATH.join("#{f}.yml")
      File.delete(path) if File.exist?(path)
      SiteConfig.reload!("features/#{f}")
    end
  end

  def member(tier: :paid, status: :active)
    Member.create!(email: "m#{Member.count}@example.com", name: "M", tier: tier, status: status)
  end

  def write_show(audience)
    path = SiteConfig::FEATURES_PATH.join("podcast.yml")
    FileUtils.mkdir_p(File.dirname(path))
    entry = PodcastConfig.default_entry.merge("title" => "The Show", "audience" => audience)
    File.write(path, { "the-show" => entry }.to_yaml.sub(/\A---\s*\n/, ""))
    SiteConfig.sync_from_file("features/podcast")
  end

  def write_release(audience)
    path = SiteConfig::FEATURES_PATH.join("music.yml")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, { "releases" => { "summer" => {
      "title" => "Summer", "synopsis" => "Tracks.", "cover" => "/media/images/c.jpg",
      "feed" => true, "audience" => audience } } }.to_yaml.sub(/\A---\s*\n/, ""))
    SiteConfig.sync_from_file("features/music")
  end

  def episode(title, type: "podcast", key: "the-show", audience: nil)
    field = type == "podcast" ? "podcast" : "release"
    meta = { "title" => title, "url_name" => title.parameterize, "status" => "published",
             "post_type" => type, field => key, "date" => "2026-01-01",
             "audio" => "/media/audio/#{title.parameterize}.mp3" }
    meta["audience"] = audience if audience
    Post.create!(file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "#{title.parameterize}.md"),
                 content: "Body.", metadata: meta)
  end

  test "a show with paid episodes is listed, with the member's token in the URL" do
    write_show("")
    episode("Paid One", audience: "paid")
    m = member

    show = PrivateFeeds.for(m).find { |f| f.kind == :podcast }

    assert_equal "The Show", show.title
    assert_equal "/podcast/the-show/private.xml?token=#{m.media_token}", show.url
  end

  # A track on a paid release carries no audience of its own and is still paid,
  # so the check has to be the resolved one.
  test "a release whose tracks are paid only by inheritance is listed" do
    write_release("paid")
    episode("Track One", type: "music", key: "summer")

    release = PrivateFeeds.for(member).find { |f| f.kind == :release }

    assert_equal "Summer", release.title
    assert_match %r{\A/music/summer/private\.xml\?token=}, release.url
  end

  # Nothing paid means nothing to subscribe to — the public feed covers it.
  test "a wholly free show is not listed" do
    write_show("")
    episode("Free One", audience: "everyone")

    assert_empty PrivateFeeds.for(member)
  end

  # Listing a URL that would 401 is worse than listing none.
  test "free and cancelled members get nothing" do
    write_show("")
    episode("Paid One", audience: "paid")

    assert_empty PrivateFeeds.for(member(tier: :free))
    assert_empty PrivateFeeds.for(member(status: :cancelled))
    assert_empty PrivateFeeds.for(nil)
  end

  # A release without a feed switched on has no URL to give out.
  test "a release with no feed is not listed" do
    path = SiteConfig::FEATURES_PATH.join("music.yml")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, { "releases" => { "summer" => {
      "title" => "Summer", "audience" => "paid" } } }.to_yaml.sub(/\A---\s*\n/, ""))
    SiteConfig.sync_from_file("features/music")
    episode("Track One", type: "music", key: "summer")

    # The main feed still appears — that paid track is in it — but the release
    # itself has no address to hand out.
    assert_empty PrivateFeeds.for(member).select { |f| f.kind == :release }
  end

  test "shows and releases appear together" do
    write_show("paid")
    episode("Ep", audience: "paid")
    write_release("paid")
    episode("Track", type: "music", key: "summer")

    assert_equal %i[podcast release],
      PrivateFeeds.for(member).map(&:kind).reject { |k| k == :feed }
  end

  # ── Named feeds ────────────────────────────────────────────────────────────
  #
  # A feed in feeds.yml can be `audience: paid` — a members-only reading feed
  # of articles, say. FeedsController#named gates it with the same token as a
  # private podcast feed, so it's just as much a thing a member subscribes to.

  def write_feeds(feeds)
    path = SiteConfig::FEATURES_PATH.join("feeds.yml")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, feeds.to_yaml.sub(/\A---\s*\n/, ""))
    SiteConfig.sync_from_file("features/feeds")
  end

  test "a paid named feed is listed" do
    write_feeds("members" => { "title" => "Members' Reading", "source" => "posts", "audience" => "paid" })
    m = member

    named = PrivateFeeds.for(m).find { |f| f.title == "Members' Reading" }

    assert_equal "/feed/members.xml?token=#{m.media_token}", named.url,
      "a feed that is itself paid is gated at its own address"
    assert_equal :feed, named.kind
  end

  test "a free named feed is not listed" do
    write_feeds("open" => { "title" => "Open", "source" => "posts" })

    assert_empty PrivateFeeds.for(member)
  end

  test "a paid named feed with no title falls back to its name" do
    write_feeds("deep-cuts" => { "source" => "posts", "audience" => "paid" })

    assert_includes PrivateFeeds.for(member).map(&:title), "Deep Cuts"
  end

  test "named feeds come before shows and releases" do
    write_feeds("members" => { "title" => "Reading", "source" => "posts", "audience" => "paid" })
    write_show("paid")
    episode("Ep", audience: "paid")

    kinds = PrivateFeeds.for(member).map(&:kind)
    assert_equal kinds.sort_by { |k| %i[feed podcast release].index(k) }, kinds,
      "feeds first, then shows, then releases"
  end
end
