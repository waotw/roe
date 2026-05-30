require "test_helper"
require "ostruct"

class FeedGeneratorTest < ActiveSupport::TestCase
  def setup
    super

    @site_config = {
      title: "Test Blog",
      url: "https://example.com",
      description: "A test blog for RSS feeds",
      author: "Test Author"
    }

    @post1 = create(:post,
      metadata: {
        "title" => "First Post",
        "status" => "published",
        "date" => "2024-01-15",
        "excerpt" => "This is the first post excerpt"
      },
      content: "# First Post\n\nContent here"
    )

    @post2 = create(:post,
      metadata: {
        "title" => "Second Post",
        "status" => "published",
        "date" => "2024-01-20"
        # No excerpt
      },
      content: "# Second Post\n\nMore content here"
    )

    @posts = Post.published.order(Arel.sql("json_extract(metadata, '$.date') DESC"))
  end

  # ============================================================================
  # RSS Feed Generation
  # ============================================================================

  test "generates valid RSS 2.0 feed" do
    generator = FeedGenerator.new(posts: @posts, format: :rss, site_config: @site_config)
    rss = generator.generate

    # Parse and validate
    feed = RSS::Parser.parse(rss, false)

    assert_instance_of RSS::Rss, feed
    assert_equal "2.0", feed.rss_version
  end

  test "RSS feed includes site metadata" do
    generator = FeedGenerator.new(posts: @posts, format: :rss, site_config: @site_config)
    rss = generator.generate

    feed = RSS::Parser.parse(rss, false)

    assert_equal "Test Blog", feed.channel.title
    assert_equal "https://example.com", feed.channel.link
    assert_equal "A test blog for RSS feeds", feed.channel.description
    assert_equal "Test Author", feed.channel.managingEditor
  end

  test "RSS feed includes all posts" do
    generator = FeedGenerator.new(posts: @posts, format: :rss, site_config: @site_config)
    rss = generator.generate

    feed = RSS::Parser.parse(rss, false)

    assert_equal 2, feed.items.count
    assert_equal "Second Post", feed.items.first.title
    assert_equal "First Post", feed.items.last.title
  end

  test "RSS feed item includes correct link" do
    generator = FeedGenerator.new(posts: @posts, format: :rss, site_config: @site_config)
    rss = generator.generate

    feed = RSS::Parser.parse(rss, false)
    item = feed.items.first

    assert_includes item.link, "https://example.com/posts/"
  end

  test "RSS feed uses excerpt when available" do
    generator = FeedGenerator.new(posts: @posts, format: :rss, site_config: @site_config)
    rss = generator.generate

    feed = RSS::Parser.parse(rss, false)

    first_post = feed.items.find { |i| i.title == "First Post" }
    assert_includes first_post.description, "This is the first post excerpt"
  end

  test "RSS feed generates description from content when no excerpt" do
    generator = FeedGenerator.new(posts: @posts, format: :rss, site_config: @site_config)
    rss = generator.generate

    feed = RSS::Parser.parse(rss, false)

    second_post = feed.items.find { |i| i.title == "Second Post" }
    assert second_post.description.present?
    # Description comes from content body, not title
    assert_includes second_post.description, "More content here"
  end

  # ============================================================================
  # Atom Feed Generation
  # ============================================================================

  test "generates valid Atom feed" do
    generator = FeedGenerator.new(posts: @posts, format: :atom, site_config: @site_config)
    atom = generator.generate

    feed = RSS::Parser.parse(atom, false)

    assert_instance_of RSS::Atom::Feed, feed
  end

  test "Atom feed includes site metadata" do
    generator = FeedGenerator.new(posts: @posts, format: :atom, site_config: @site_config)
    atom = generator.generate

    feed = RSS::Parser.parse(atom, false)

    assert_equal "Test Blog", feed.title.content
    assert_equal "https://example.com", feed.id.content
  end

  test "Atom feed includes all posts" do
    generator = FeedGenerator.new(posts: @posts, format: :atom, site_config: @site_config)
    atom = generator.generate

    feed = RSS::Parser.parse(atom, false)

    assert_equal 2, feed.entries.count
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  test "handles empty posts collection" do
    generator = FeedGenerator.new(posts: Post.none, format: :rss, site_config: @site_config)
    rss = generator.generate

    feed = RSS::Parser.parse(rss, false)

    assert_equal 0, feed.items.count
  end

  test "handles posts without dates" do
    post_no_date = create(:post,
      metadata: {
        "title" => "No Date Post",
        "status" => "published"
      },
      content: "# No Date"
    )

    posts = Post.where(id: post_no_date.id)
    generator = FeedGenerator.new(posts: posts, format: :rss, site_config: @site_config)
    rss = generator.generate

    feed = RSS::Parser.parse(rss, false)

    assert_equal 1, feed.items.count
  end

  test "handles missing site config gracefully" do
    generator = FeedGenerator.new(posts: @posts, format: :rss, site_config: {})
    rss = generator.generate

    # Should generate without errors
    feed = RSS::Parser.parse(rss, false)
    assert feed.channel.title.present? || feed.channel.title.to_s.empty?
  end

  test "raises error for unsupported format" do
    assert_raises(ArgumentError) do
      generator = FeedGenerator.new(posts: @posts, format: :json, site_config: @site_config)
      generator.generate
    end
  end

  # ============================================================================
  # Initialization Options
  # ============================================================================

  test "accepts include_paid option" do
    generator = FeedGenerator.new(
      posts: @posts,
      format: :rss,
      site_config: @site_config,
      include_paid: true
    )

    assert generator.include_paid
  end

  test "accepts show_paid_teasers option" do
    generator = FeedGenerator.new(
      posts: @posts,
      format: :rss,
      site_config: @site_config,
      show_paid_teasers: true
    )

    assert generator.show_paid_teasers
  end

  test "accepts podcast_config for podcast feeds" do
    podcast_config = OpenStruct.new(
      title: "Test Podcast",
      description: "A test podcast"
    )

    generator = FeedGenerator.new(
      posts: @posts,
      format: :podcast,
      site_config: @site_config,
      podcast_config: podcast_config
    )

    assert_equal podcast_config, generator.podcast_config
  end

  # ============================================================================
  # GUID Generation
  # ============================================================================

  test "generates unique GUIDs for each post" do
    generator = FeedGenerator.new(posts: @posts, format: :rss, site_config: @site_config)
    rss = generator.generate

    feed = RSS::Parser.parse(rss, false)

    guids = feed.items.map { |item| item.guid.content }
    assert_equal guids.uniq.count, guids.count
  end

  test "GUIDs are permanent links" do
    generator = FeedGenerator.new(posts: @posts, format: :rss, site_config: @site_config)
    rss = generator.generate

    feed = RSS::Parser.parse(rss, false)

    feed.items.each do |item|
      assert item.guid.isPermaLink
    end
  end
end
