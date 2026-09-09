require "test_helper"

class Admin::FeedImportsControllerTest < ActionDispatch::IntegrationTest
  PODCAST_YML = PodcastConfigSeeder::PODCAST_YML

  setup do
    @user = User.take
    sign_in_as(@user)
    @podcast_yml_backup = File.exist?(PODCAST_YML) ? File.read(PODCAST_YML) : :absent
  end

  teardown do
    if @podcast_yml_backup == :absent
      File.delete(PODCAST_YML) if File.exist?(PODCAST_YML)
    else
      File.write(PODCAST_YML, @podcast_yml_backup)
    end
    SiteConfig.reload!("features/podcast") rescue nil
  end

  def feed_result(fixture)
    data = PodcastFeedParser.parse(File.read(Rails.root.join("test", "fixtures", "feeds", fixture)))
    PodcastFeedFetcher::Result.new(success?: true, data: data, error: nil)
  end

  def write_podcast_config(shows)
    FileUtils.mkdir_p(File.dirname(PODCAST_YML))
    File.write(PODCAST_YML, shows.to_yaml.sub(/\A---\s*\n/, ""))
    SiteConfig.reload!("features/podcast")
  end

  def show_entry(title)
    { "title" => title, "link" => "", "apple_podcasts" => "" }
  end

  test "index renders the paste form" do
    get admin_feed_imports_path
    assert_response :success
    assert_select "form[action=?]", preview_admin_feed_imports_path
  end

  test "preview classifies a feed and offers import options" do
    PodcastFeedFetcher.stubs(:fetch).returns(feed_result("verge.xml"))
    post preview_admin_feed_imports_path, params: { feed_url: "https://theverge.com/rss.xml" }
    assert_response :success
    assert_select "form[action=?]", admin_feed_imports_path
    assert_select "input[name=kind][value=articles]"
  end

  test "preview requires a url" do
    post preview_admin_feed_imports_path, params: { feed_url: "   " }
    assert_response :unprocessable_entity
    assert_equal "Paste a feed URL or an Apple Podcasts link.", flash[:alert]
  end

  test "preview pre-selects the show that matches the feed, not the first one" do
    feed  = feed_result("npr_all_songs.xml")
    title = feed.data[:channel][:title]
    key   = PodcastConfigSeeder.derive_key(title)
    write_podcast_config(
      "the-briefcast-podcast" => show_entry("The Briefcast: Podcast"),
      key                     => show_entry(title)
    )

    PodcastFeedFetcher.stubs(:fetch).returns(feed)
    post preview_admin_feed_imports_path, params: { feed_url: "https://example.com/atc" }

    assert_response :success
    assert_select "select[name=podcast_key] option[selected][value=?]", key
    assert_select "select[name=podcast_key] option[selected]", count: 1
  end

  test "add_show seeds a show from the feed and re-renders with it selected" do
    # A show already exists — and materialize its config DB row so a bare
    # cache-clear would leave that row stale (the real-app bug: the new show
    # would then be missing from the select).
    write_podcast_config("the-briefcast-podcast" => show_entry("The Briefcast: Podcast"))
    PodcastConfig.podcast_keys

    # No image_url in the channel, so no artwork download (no network).
    data = {
      channel: { title: "Fresh Cast", link: "https://freshcast.fm", author: "Ana", description: "hi" },
      items: [ { title: "Ep 1", guid: "g1", enclosure_url: "https://freshcast.fm/1.mp3", enclosure_type: "audio/mpeg", duration: "600" } ]
    }
    PodcastFeedFetcher.stubs(:fetch).returns(PodcastFeedFetcher::Result.new(success?: true, data: data, error: nil))

    post add_show_admin_feed_imports_path, params: { feed_url: "https://freshcast.fm/feed.xml", podcast_title: "Fresh Cast" }

    assert_response :success
    assert_select "select[name=podcast_key] option[value=?]", "the-briefcast-podcast" # existing show still listed
    assert_select "select[name=podcast_key] option[selected][value=?]", "fresh-cast"  # new show listed + pre-selected
    assert_includes File.read(PODCAST_YML), "fresh-cast:"
  end

  test "importing episodes without a podcast show is rejected" do
    post admin_feed_imports_path, params: { feed_url: "https://x/feed.xml", kind: "episodes" }
    assert_redirected_to admin_feed_imports_path
    assert_equal "Pick a podcast show for the episodes, or set one up first.", flash[:alert]
  end

  test "importing articles creates drafts and redirects to the drafts list" do
    before = Dir[File.join(RoeSitePaths::SITE_POSTS_PATH, "*.md")]
    PodcastFeedFetcher.stubs(:fetch).returns(feed_result("verge.xml"))
    post admin_feed_imports_path,
         params: { feed_url: "https://theverge.com/rss.xml", kind: "articles", count_mode: "all" }
    assert_redirected_to admin_posts_path(status: "draft", sort: "updated-desc")
    assert_match(/Imported \d+ articles as drafts/, flash[:notice])
  ensure
    (Dir[File.join(RoeSitePaths::SITE_POSTS_PATH, "*.md")] - before).each { |f| File.delete(f) }
  end

  test "importing records a feed import that is listed and can be deleted" do
    before = Dir[File.join(RoeSitePaths::SITE_POSTS_PATH, "*.md")]
    PodcastFeedFetcher.stubs(:fetch).returns(feed_result("verge.xml"))

    assert_difference -> { Import.where(source_type: "feed").count }, 1 do
      post admin_feed_imports_path,
           params: { feed_url: "https://theverge.com/rss.xml", kind: "articles", count_mode: "all" }
    end

    import = Import.where(source_type: "feed").order(:id).last
    assert_equal 3, import.stats["imported"].to_i
    assert_operator import.ref_draft_count, :>=, 1, "episodes/articles tagged with import_ref"

    get admin_feed_imports_path
    assert_response :success
    assert_select "a", text: "Import ##{import.id}"

    assert_difference -> { Import.count }, -1 do
      delete admin_feed_import_path(import)
    end
    assert_equal 0, Post.where("json_extract(metadata, '$.import_ref') = ?", import.id).count
  ensure
    (Dir[File.join(RoeSitePaths::SITE_POSTS_PATH, "*.md")] - before).each { |f| File.delete(f) }
  end
end
