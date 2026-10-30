# frozen_string_literal: true

require "test_helper"

module SiteSync
  # What goes into a backup. Video web versions are made from the original
  # and stay out; their -video.json holds choices and stays in.
  class BackupPolicyTest < ActiveSupport::TestCase
    test "video web versions are recognised, their settings file is not" do
      assert BackupPolicy.video_web_version?("media/video/variants/clip-720p.mp4")
      assert BackupPolicy.video_web_version?("media/video/variants/clip-poster.jpg")
      assert BackupPolicy.video_web_version?("media/video/sub/variants/clip-1080p.mp4")
      assert BackupPolicy.video_web_version?("/media/video/variants/clip-720p.mp4")

      assert_not BackupPolicy.video_web_version?("media/video/variants/clip-video.json")
      assert_not BackupPolicy.video_web_version?("media/video/clip.mp4")
      assert_not BackupPolicy.video_web_version?("posts/variants/notes.md")
    end
  end
end
