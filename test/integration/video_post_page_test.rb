require "test_helper"
require_relative "../video_test_helpers"

# The video post page and the podcast player both serve a video's web
# versions through VideoRenderer, end to end through the real views.
class VideoPostPageTest < ActionDispatch::IntegrationTest
  include VideoTestHelpers

  setup { setup_video_dir }
  teardown { teardown_video_dir }

  def video_post(type, web)
    create(:post,
      metadata: { "title" => "Clip #{type}", "status" => "published", "date" => "2024-01-01",
                  "audience" => "everyone", "post_type" => type, "video" => web },
      content: "Words.")
  end

  test "a video post plays the 720p version with its poster, in the site player" do
    web = fake_variants("post-clip.mov", renditions: %w[720p 1080p])
    post = video_post("video", web)

    get post_path(post.url_name)
    assert_response :success
    assert_select ".video-player-container[data-player=video] video.video-player-video[controls][poster=?]", "/media/video/variants/post-clip-poster.jpg"
    assert_select "video.video-player-video source", 2
    assert_select "video.video-player-video source:first-child[src=?]", "/media/video/variants/post-clip-720p.mp4"
    assert_select ".video-player-container [data-player-ui][hidden] [data-player-part=play]"
    assert_no_match(%r{post-clip\.mov}, response.body.scan(/<video.*?<\/video>/m).join, "the 1 GB original isn't offered, not even as the download link")
  end

  test "a video podcast's player keeps its episode buttons" do
    web = fake_variants("pod-clip.mp4")
    post = video_post("podcast", web)

    get post_path(post.url_name)
    assert_response :success
    assert_select "video[data-player-part=media] source[src=?]", "/media/video/variants/pod-clip-720p.mp4"
    assert_select ".video-player-container .btn-episode-nav", 2
  end

  test "a plain video post has no episode buttons" do
    post = video_post("video", fake_variants("plain.mp4"))

    get post_path(post.url_name)
    assert_select ".video-player-container .btn-episode-nav", 0
  end
end
