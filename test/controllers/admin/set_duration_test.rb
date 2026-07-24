require "test_helper"

class Admin::SetDurationTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    @created = []
  end
  teardown { @created.each { |f| File.delete(f) if File.exist?(f) } }

  def make_post(name, meta)
    slug = ContentWriter.new.write(kind: :post, filename: name, metadata: meta.merge("title" => name), body: "b")
    @created << File.join(RoeSitePaths::SITE_POSTS_PATH, "#{slug}.md")
    Post.find_by("json_extract(metadata, '$.url_name') = ?", slug)
  end

  test "set_duration fills a blank duration" do
    post = make_post("sd-a", { "post_type" => "podcast", "audio" => "/media/audio/x.mp3", "status" => "draft" })
    patch set_duration_admin_post_path(post), params: { duration: "00:42:15" }
    assert_response :success
    assert_equal "00:42:15", post.reload.metadata["duration"]
  end

  test "set_duration never clobbers an existing duration" do
    post = make_post("sd-b", { "post_type" => "podcast", "audio" => "/media/audio/x.mp3", "duration" => "01:00:00", "status" => "draft" })
    patch set_duration_admin_post_path(post), params: { duration: "00:42:15" }
    assert_response :no_content
    assert_equal "01:00:00", post.reload.metadata["duration"]
  end

  test "set_duration rejects a malformed value" do
    post = make_post("sd-c", { "post_type" => "podcast", "audio" => "/media/audio/x.mp3", "status" => "draft" })
    patch set_duration_admin_post_path(post), params: { duration: "banana" }
    assert_response :unprocessable_entity
  end

  test "posts index emits a duration item only for episodes missing duration" do
    make_post("sd-missing", { "post_type" => "podcast", "audio" => "https://cdn.example.com/x.mp3", "status" => "draft" })
    make_post("sd-hasdur", { "post_type" => "podcast", "audio" => "https://cdn.example.com/y.mp3", "duration" => "00:05:00", "status" => "draft" })

    get admin_posts_path
    assert_response :success
    assert_select "[data-controller~=?]", "episode-durations"
    assert_select "span[data-episode-durations-target=item][data-media-url=?]", "https://cdn.example.com/x.mp3"
    assert_select "span[data-episode-durations-target=item][data-media-url=?]", "https://cdn.example.com/y.mp3", false
  end
end
