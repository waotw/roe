# frozen_string_literal: true

require "test_helper"

# The Download button in the Media Browser's selection bar. It's for keeping
# a copy of something from the live site — large videos aren't in the backup
# a sync takes — so it only shows there. Locally the files are already in
# site/media.
class Admin::MediumDownloadTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    path = "/media/images/zz-download-test.jpg"
    @absolute = File.join(RoeSitePaths::SITE_PATH, path.delete_prefix("/"))
    FileUtils.mkdir_p(File.dirname(@absolute))
    File.write(@absolute, "bytes")
    Medium.find_or_create_by!(file_path: path) { |m| m.media_type = "images" }
  end

  teardown do
    Medium.where(file_path: "/media/images/zz-download-test.jpg").destroy_all
    FileUtils.rm_f(@absolute)
  end

  def download_button = %r{media-bulk-select#downloadSelected}

  test "shown on the live site, with each file's address on its checkbox" do
    Rails.env.stubs(:production?).returns(true)
    get browse_admin_medium_index_path

    assert_response :success
    assert_match download_button, response.body
    assert_match %(data-file-path="/media/images/zz-download-test.jpg"), response.body
  end

  test "not shown locally" do
    get browse_admin_medium_index_path

    assert_response :success
    assert_no_match download_button, response.body
  end
end
