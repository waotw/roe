# frozen_string_literal: true

require "test_helper"

# The editor's duration field asks /admin/medium/duration about a YouTube
# link, since a <video> tag can't read one (media_duration.js).
class Admin::MediumDurationTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }

  test "a YouTube link's length comes back as HH:MM:SS" do
    VideoEmbed.any_instance.stubs(:duration_seconds).returns(3723)

    get duration_admin_medium_index_path(path: "https://youtu.be/dQw4w9WgXcQ?si=x")

    assert_response :success
    assert_equal "01:02:03", JSON.parse(response.body)["duration"]
  end

  test "a length YouTube won't give says so, and the field is left alone" do
    VideoEmbed.any_instance.stubs(:duration_seconds).returns(nil)

    get duration_admin_medium_index_path(path: "https://youtu.be/dQw4w9WgXcQ")

    assert_response :unprocessable_entity
    assert_match "YouTube", JSON.parse(response.body)["error"]
  end

  test "a link to some other site is not fetched" do
    VideoEmbed.any_instance.expects(:duration_seconds).never

    get duration_admin_medium_index_path(path: "https://example.com/page")

    assert_response :not_found
  end

  test "only files under site/media are read" do
    MediaDurationExtractor.expects(:extract).never

    get duration_admin_medium_index_path(path: "/media/../config/master.key")
    assert_response :not_found

    get duration_admin_medium_index_path(path: "system/global/site.yml")
    assert_response :not_found
  end
end
