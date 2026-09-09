require "test_helper"

# End-to-end coverage for named feeds (feeds.yml → /feed/<name>.xml|.atom).
# Feed configs are stubbed for determinism; posts are real so selection,
# paid-exclusion, and rendering run through the true stack.
class NamedFeedsTest < ActionDispatch::IntegrationTest
  setup { @created = [] }
  teardown { @created.each { |f| File.delete(f) if File.exist?(f) } }

  def write_post(name, extra = {})
    meta = { "title" => name.tr("-", " "), "url_name" => name,
             "status" => "published", "date" => "2026-01-01" }.merge(extra)
    slug = ContentWriter.new.write(kind: :post, filename: name, metadata: meta, body: "Body of #{name}")
    @created << File.join(RoeSitePaths::SITE_POSTS_PATH, "#{slug}.md")
    slug
  end

  def stub_feed(config)
    FeedConfig.stubs(:all_feeds).returns({ "articles" => config })
  end

  test "an unknown feed is 404" do
    FeedConfig.stubs(:all_feeds).returns({})
    get "/feed/missing.xml"
    assert_response :not_found
  end

  test "a free feed renders RSS including a matching post" do
    write_post("nf-article", "post_type" => "article")
    stub_feed({ "title" => "Articles", "source" => "posts", "post_type" => "article" })

    get "/feed/articles.xml"

    assert_response :success
    assert_match %r{application/rss\+xml}, response.content_type
    assert_includes response.body, "nf-article"
  end

  test "the .atom variant renders atom" do
    write_post("nf-atom", "post_type" => "article")
    stub_feed({ "source" => "posts", "post_type" => "article" })

    get "/feed/articles.atom"

    assert_response :success
    assert_match %r{application/atom\+xml}, response.content_type
  end

  test "a free feed excludes paid content when members is enabled" do
    write_post("nf-free", "post_type" => "article")
    write_post("nf-paid", "post_type" => "article", "audience" => "paid")
    stub_feed({ "source" => "posts", "post_type" => "article" })
    SiteConfig.stubs(:feature_enabled?).returns(false)
    SiteConfig.stubs(:feature_enabled?).with("members").returns(true)

    get "/feed/articles.xml"

    assert_response :success
    assert_includes response.body, "nf-free"
    assert_not_includes response.body, "nf-paid", "a public feed must not leak paid content"
  end

  test "a paid feed is unauthorized without a token" do
    stub_feed({ "source" => "posts", "audience" => "paid" })

    get "/feed/articles.xml"

    assert_response :unauthorized
  end
end
