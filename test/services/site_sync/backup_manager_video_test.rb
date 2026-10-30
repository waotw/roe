# frozen_string_literal: true

require "test_helper"
require "fileutils"

module SiteSync
  # Local snapshots leave video web versions out — they're made again from
  # the original — but keep each video's -video.json, which records choices
  # that can't be rebuilt. Restoring a snapshot must not then delete the
  # web versions /site has now.
  class BackupManagerVideoTest < ActiveSupport::TestCase
    SITE = RoeSitePaths::SITE_PATH
    DIR  = "media/video/zz-backup-test"

    FILES = {
      "#{DIR}/clip.mp4"                  => "original",
      "#{DIR}/variants/clip-720p.mp4"    => "rendition",
      "#{DIR}/variants/clip-poster.jpg"  => "poster",
      "#{DIR}/variants/clip-video.json"  => "{\"poster_at\":3.4}"
    }.freeze

    def setup
      FILES.each do |rel, body|
        path = File.join(SITE, rel)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, body)
      end
      @snapshots = []
    end

    def teardown
      FileUtils.rm_rf(File.join(SITE, DIR))
      @snapshots.each { |path| FileUtils.rm_rf(path) }
    end

    def snapshot!
      BackupManager.create.tap { |path| @snapshots << path }
    end

    test "a snapshot keeps the original and -video.json but not the web versions" do
      snap = snapshot!

      assert File.exist?(File.join(snap, "#{DIR}/clip.mp4"))
      assert File.exist?(File.join(snap, "#{DIR}/variants/clip-video.json"))
      assert_not File.exist?(File.join(snap, "#{DIR}/variants/clip-720p.mp4"))
      assert_not File.exist?(File.join(snap, "#{DIR}/variants/clip-poster.jpg"))
    end

    test "restoring a snapshot leaves the current web versions alone" do
      snap = snapshot!
      edited = File.join(SITE, "#{DIR}/variants/clip-video.json")
      File.write(edited, "{\"poster_at\":9.9}")
      # Same length, same second: rsync would take it as unchanged. A real
      # edit comes later than the snapshot.
      File.utime(Time.now + 60, Time.now + 60, edited)

      # Snapshots are named to the second; restore's own safety snapshot
      # would otherwise land in the same folder as the one being restored.
      travel 2.seconds
      result = BackupManager.restore(File.basename(snap))
      @snapshots << result[:safety_path]

      assert_equal "rendition", File.read(File.join(SITE, "#{DIR}/variants/clip-720p.mp4"))
      assert_equal "poster", File.read(File.join(SITE, "#{DIR}/variants/clip-poster.jpg"))
      assert_equal "{\"poster_at\":3.4}", File.read(File.join(SITE, "#{DIR}/variants/clip-video.json"))
    end

    # The backup list marks the snapshot matching /site as "active". /site has
    # web versions the snapshot doesn't, and that mustn't count as a change.
    test "a fresh snapshot is still marked as matching the site" do
      snap = snapshot!
      Rails.cache.delete("site_sync:current_fingerprint")

      entry = BackupManager.list.find { |s| s[:path] == snap }
      assert entry[:active], "web versions left out of the snapshot shouldn't count as a difference"
    end
  end
end
