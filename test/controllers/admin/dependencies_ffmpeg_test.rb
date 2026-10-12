require "test_helper"

# The Dependencies page lists ffmpeg with the others, and says which half is
# missing when only one of ffmpeg / ffprobe is found.
class Admin::DependenciesFfmpegTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:one)) }

  test "ffmpeg is listed with its install command when missing" do
    ManagedTools::Platform.stubs(:find_executable).returns(nil)

    get admin_dependencies_path
    assert_response :success
    assert_match(/>\s*ffmpeg\s*</, response.body)
    assert_match(/Video conversion tool/, response.body)
    assert_match(/install(?: -y)? ffmpeg/, response.body)
    assert_no_match(/Found ffmpeg but not ffprobe/, response.body)
  end

  test "says ffprobe is missing when only ffmpeg is found" do
    ManagedTools::Platform.stubs(:find_executable).returns(nil)
    ManagedTools::Platform.stubs(:find_executable).with("ffmpeg").returns("/x/ffmpeg")

    get admin_dependencies_path
    assert_match(/Found ffmpeg but not ffprobe/, response.body)
  end
end
