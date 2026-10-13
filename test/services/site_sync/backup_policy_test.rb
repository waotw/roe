# frozen_string_literal: true

require "test_helper"

module SiteSync
  # What goes into a backup. Video web versions are made from the original
  # and stay out; their -video.json holds choices and stays in. Live backups
  # also skip anything over the size limit, which is what used to fail and
  # stop the sync.
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

    test "live backups keep small files and set aside large ones" do
      limit = BackupPolicy::LIVE_BACKUP_MAX_BYTES
      peer = {
        "posts/a.md"                          => { "size" => 100 },
        "media/video/clip.mov"                => { "size" => limit + 1 },
        "media/video/at-limit.mp4"            => { "size" => limit },
        "media/video/variants/clip-720p.mp4"  => { "size" => 10 },
        "media/video/variants/clip-video.json" => { "size" => 10 }
      }

      keep, too_large = BackupPolicy.partition_live_backup(peer.keys, peer)

      assert_equal %w[posts/a.md media/video/at-limit.mp4 media/video/variants/clip-video.json], keep
      assert_equal %w[media/video/clip.mov], too_large
    end
  end
end
