require "test_helper"

# The newsletter and feed items follow the post's layout: the same parts in
# the same order as the page, each in a form that works there.
class ContentLayoutTextTest < ActiveSupport::TestCase
  teardown do
    Dir.glob(File.join(ContentLayout::SITE_DIR, "*#{ContentLayout::EXT}")).each { |f| FileUtils.rm_f(f) }
  end

  def a_post(type = "article", **fields)
    @n = (@n || 0) + 1
    create(:post,
      metadata: { "title" => "Post #{@n}", "status" => "published", "date" => "2024-03-05",
                  "audience" => "everyone", "post_type" => type }.merge(fields.transform_keys(&:to_s)),
      content: "Words.")
  end

  def text(post, mode)
    ContentLayout::Text.new(post, mode: mode, body_html: "<p>Words.</p>").html
  end

  def site_layout(name, list)
    FileUtils.mkdir_p(ContentLayout::SITE_DIR)
    path = ContentLayout.site_path(name)
    File.write(path, list)
    File.utime(Time.now + rand(1..1000), Time.now + rand(1..1000), path)
  end

  test "the email has the title, subtitle, date and author, then the body" do
    html = text(a_post(subtitle: "A subtitle", author: "Ben"), :email)

    assert_match %r{<h1>Post \d+</h1>}, html
    assert_includes html, %(<p class="post-subtitle">A subtitle</p>)
    assert_match(/March 05, 2024.*By Ben/m, html)
    assert_operator html.index("A subtitle"), :<, html.index("Words.")
  end

  test "a feed item leaves out the title, date and author, which the reader shows" do
    html = text(a_post(subtitle: "A subtitle", author: "Ben"), :feed)

    assert_not_includes html, "<h1>"
    assert_not_includes html, "March 05"
    assert_not_includes html, "Ben"
    assert_includes html, "A subtitle"
    assert_includes html, "Words."
  end

  test "the order follows the site's layout" do
    site_layout("article", "[body]\n[subtitle]\n")
    html = text(a_post(subtitle: "After"), :feed)
    assert_operator html.index("Words."), :<, html.index("After")
  end

  test "the player is a Listen link in email and feeds, and nothing in a podcast feed" do
    audio = a_post("audio", audio: "/media/audio/a.mp3")
    assert_match %r{<a href="http[^"]+/posts/#{audio.url_name}">Listen</a>}, text(audio, :email)
    assert_includes text(audio, :feed), ">Listen</a>"

    episode = a_post("podcast", audio: "/media/audio/e.mp3", podcast: "show")
    assert_not_includes text(episode, :podcast_feed), "Listen"
  end

  test "a YouTube video is its thumbnail, linking to it" do
    html = text(a_post("video", video: "https://youtu.be/dQw4w9WgXcQ"), :email)
    assert_includes html, "video-external-link"
    assert_not_includes html, ">Watch</a>"
  end

  test "an article's feed link is a plain link in email, and left out of the feed itself" do
    assert_match %r{<p class="feed-links"><a href="http[^"]+/feed\.xml">RSS</a></p>}, text(a_post, :email)
    assert_not_includes text(a_post, :feed), "feed.xml"
  end

  test "site-only parts and a layout without the title draw nothing extra" do
    site_layout("article", "[episodes]\n[buy_button]\n[body]\n")
    assert_equal "<p>Words.</p>", text(a_post, :email).gsub(%r{</?div[^>]*>}, "").strip
  end

  test "the newsletter email uses the layout" do
    site_layout("article", "[subtitle]\n[body]\n")
    html = NewsletterRenderer.new(a_post(subtitle: "Only this")).preview
    assert_includes html, "Only this"
    assert_not_includes html, "<h1>", "the site's layout has no title"
  end
end
