require "test_helper"

class Admin::FeedImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.take
    sign_in_as(@user)
  end

  def feed_result(fixture)
    data = PodcastFeedParser.parse(File.read(Rails.root.join("test", "fixtures", "feeds", fixture)))
    PodcastFeedFetcher::Result.new(success?: true, data: data, error: nil)
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
end
