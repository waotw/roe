require "test_helper"

# A YouTube Share link in a post's `video:` field, or in its body, plays in
# YouTube's own player. End to end through the real views and pipeline.
class YoutubeVideoTest < ActionDispatch::IntegrationTest
  SHARE = "https://youtu.be/dQw4w9WgXcQ?si=Zx1&t=42".freeze

  def video_post(type, video, content: "Words.")
    create(:post,
      metadata: { "title" => "Talk #{type}", "status" => "published", "date" => "2024-01-01",
                  "audience" => "everyone", "post_type" => type, "video" => video },
      content: content)
  end

  test "a video post with a Share link plays YouTube's player, from the shared time" do
    post = video_post("video", SHARE)

    get post_path(post.url_name)
    assert_response :success
    assert_select ".video-external.video-external-youtube iframe[src=?][title=?]",
                  "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?rel=0&start=42", "Talk video"
    assert_select "iframe[allowfullscreen][loading=lazy][referrerpolicy=strict-origin-when-cross-origin]"
    assert_select "video", 0, "no <video> tag pointing at a YouTube page"
  end

  test "a video podcast with a YouTube link plays it too" do
    post = video_post("podcast", "https://www.youtube.com/watch?v=dQw4w9WgXcQ")

    get post_path(post.url_name)
    assert_select ".video-external iframe[src^=?]", "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ"
  end

  test "a Share link alone on a line of the body becomes the player; one in a sentence stays a link" do
    post = video_post("article", nil, content: "Intro.\n\n#{SHARE}\n\nOr watch it at #{SHARE} later.")

    get post_path(post.url_name)
    assert_select ".post-content .video-external iframe", 1
    assert_select ".post-content p", text: /Or watch it at https:\/\/youtu\.be/
    assert_no_match(%r{<p>\s*<div class="video-external}, response.body, "the player isn't left inside a <p>")
  end

  test "with no image of its own, the post shares with the video's thumbnail" do
    post = video_post("video", SHARE)

    get post_path(post.url_name)
    assert_select "meta[property='og:image'][content=?]", "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"
  end

  test "the newsletter carries the video as a thumbnail linking to it" do
    post = video_post("video", SHARE)

    html = NewsletterRenderer.new(post).preview
    assert_not_includes html, "<iframe"
    assert_includes html, %(href="https://www.youtube.com/watch?v=dQw4w9WgXcQ&amp;t=42")
    assert_includes html, "▶ Talk video"
  end
end
