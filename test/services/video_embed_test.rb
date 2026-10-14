require "test_helper"

# VideoEmbed recognises the links people copy from YouTube — the Share
# button's youtu.be form above all — and nothing else.
class VideoEmbedTest < ActiveSupport::TestCase
  ID = "dQw4w9WgXcQ".freeze

  test "every common YouTube link form gives the video's id" do
    [
      "https://youtu.be/#{ID}",
      "https://youtu.be/#{ID}?si=AbC123xyz",
      "https://www.youtube.com/watch?v=#{ID}",
      "https://youtube.com/watch?v=#{ID}&list=PL123&index=2",
      "https://m.youtube.com/watch?feature=share&v=#{ID}",
      "https://music.youtube.com/watch?v=#{ID}",
      "https://www.youtube.com/embed/#{ID}",
      "https://www.youtube-nocookie.com/embed/#{ID}",
      "https://www.youtube.com/live/#{ID}?si=x",
      "http://youtu.be/#{ID}"
    ].each do |url|
      assert_equal ID, VideoEmbed.for(url)&.id, url
    end
  end

  test "a start time comes through in every form YouTube writes it" do
    assert_equal 42,   VideoEmbed.for("https://youtu.be/#{ID}?t=42").start
    assert_equal 42,   VideoEmbed.for("https://youtu.be/#{ID}?t=42s").start
    assert_equal 90,   VideoEmbed.for("https://www.youtube.com/watch?v=#{ID}&t=1m30s").start
    assert_equal 3723, VideoEmbed.for("https://www.youtube.com/watch?v=#{ID}&t=1h2m3s").start
    assert_equal 5,    VideoEmbed.for("https://www.youtube.com/embed/#{ID}?start=5").start
    assert_nil VideoEmbed.for("https://youtu.be/#{ID}").start
    assert_nil VideoEmbed.for("https://youtu.be/#{ID}?t=0").start
  end

  test "Shorts are vertical" do
    assert VideoEmbed.for("https://www.youtube.com/shorts/#{ID}").vertical?
    assert_not VideoEmbed.for("https://youtu.be/#{ID}").vertical?
  end

  test "anything else is not an embed" do
    [
      "/media/video/clip.mp4",
      "https://example.com/clip.mp4",
      "https://vimeo.com/123456",
      "https://www.youtube.com/@somechannel",
      "https://www.youtube.com/watch?v=tooshort",
      "https://www.youtube.com/playlist?list=PL123",
      "https://notyoutube.com/watch?v=#{ID}",
      "javascript:alert(1)",
      "",
      nil
    ].each do |src|
      assert_nil VideoEmbed.for(src), src.inspect
    end
  end

  test "the player uses YouTube's privacy-enhanced address and escapes its title" do
    html = VideoEmbed.for("https://youtu.be/#{ID}?t=7").iframe_html(label: %(A "quoted" <title>))

    assert_includes html, %(src="https://www.youtube-nocookie.com/embed/#{ID}?rel=0&amp;start=7")
    assert_includes html, %(title="A &quot;quoted&quot; &lt;title&gt;")
    assert_includes html, "allowfullscreen"
  end

  test "the link version points at the video on YouTube, with its thumbnail" do
    html = VideoEmbed.for("https://youtu.be/#{ID}?t=7").link_html(label: "My talk")

    assert_includes html, %(href="https://www.youtube.com/watch?v=#{ID}&amp;t=7")
    assert_includes html, %(src="https://i.ytimg.com/vi/#{ID}/hqdefault.jpg")
    assert_includes html, "▶ My talk"
  end

  # Markdown: what an author types, through the whole pipeline.
  def render(md, **opts) = Post.new(content: md, file_path: "x.md").to_html(**opts).to_s

  test "![title](link) and a link alone on its line both play" do
    html = render("![My talk](https://youtu.be/#{ID})\n\nhttps://youtu.be/#{ID}\n\n<https://youtu.be/#{ID}>")

    assert_equal 3, html.scan("<iframe").size
    assert_includes html, %(title="My talk")
    assert_no_match(/<img[^>]*youtu/, html, "never an <img> pointing at a YouTube page")
  end

  test "a link inside a sentence, or with its own text, stays a link" do
    html = render("Watch https://youtu.be/#{ID} now.\n\n[the video](https://youtu.be/#{ID})")

    assert_not_includes html, "<iframe"
  end

  test "feeds and email get a thumbnail link, since they strip iframes" do
    md = "![My talk](https://youtu.be/#{ID})"

    feed = render(md, feed: true)
    assert_not_includes feed, "<iframe"
    assert_includes feed, "https://www.youtube.com/watch?v=#{ID}"

    email = NewsletterImageTransformer.transform(render(md), site_url: "https://example.com")
    assert_not_includes email, "<iframe"
    assert_includes email, "https://i.ytimg.com/vi/#{ID}/hqdefault.jpg"
    assert_includes email, "▶ My talk"
  end
end
