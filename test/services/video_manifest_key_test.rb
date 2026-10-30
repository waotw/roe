require "test_helper"
require_relative "../video_test_helpers"

# A -video.json lists its web versions under "variants". Before 0.4.0 the
# list was called "renditions"; those files must keep working exactly as
# before, with nothing rewritten, until Roe next saves them.
class VideoManifestKeyTest < ActiveSupport::TestCase
  include VideoTestHelpers
  include ActiveJob::TestHelper

  setup { setup_video_dir }
  teardown { teardown_video_dir }

  test "a manifest from before 0.4.0, with \"renditions\", still serves its variants" do
    web = fake_variants("older.mp4", renditions: %w[720p 1080p], key: "renditions")
    source = VideoVariantGenerator.normalize_path(web)

    assert_equal %w[720p 1080p], VideoVariantGenerator.available_renditions(source).map { |r| r["name"] }
    assert VideoVariantGenerator.complete?(source)
    assert_includes VideoRenderer.tag(web), "older-720p.mp4", "the page plays the 720p, not the original"

    raw = JSON.parse(File.read(VideoVariantGenerator.manifest_path(source)))
    assert raw.key?("renditions"), "reading it doesn't rewrite the file"
  end

  test "a manifest with \"variants\" is read the same way" do
    web = fake_variants("newer.mp4", renditions: %w[720p])
    source = VideoVariantGenerator.normalize_path(web)

    assert_equal %w[720p], VideoVariantGenerator.available_renditions(source).map { |r| r["name"] }
    assert_includes VideoRenderer.tag(web), "newer-720p.mp4"
  end

  test "reading gives one list, under the new name" do
    upgraded = VideoVariantGenerator.upgrade_manifest({ "renditions" => [ { "name" => "720p" } ] })
    assert_equal [ { "name" => "720p" } ], upgraded["variants"]
    assert_not upgraded.key?("renditions")

    both = VideoVariantGenerator.upgrade_manifest({ "variants" => [ { "name" => "1080p" } ], "renditions" => [ { "name" => "720p" } ] })
    assert_equal [ { "name" => "1080p" } ], both["variants"], "the new name wins when a file has both"
  end

  test "a saved manifest carries both names, and reads back as one list" do
    saved = VideoVariantGenerator.for_file({ "variants" => [ { "name" => "720p" } ], "complete" => true })
    assert_equal saved["variants"], saved["renditions"]

    read = VideoVariantGenerator.upgrade_manifest(JSON.parse(saved.to_json))
    assert_equal [ { "name" => "720p" } ], read["variants"]
    assert_not read.key?("renditions")
  end

  # Updating Roe must not give Site Sync anything to send for a video that's
  # already done: no file rewritten, nothing queued to be made again.
  test "after an update, a finished video's files are left exactly as they were" do
    web = fake_variants("done.mp4", renditions: %w[720p 1080p], key: "renditions")
    source = VideoVariantGenerator.normalize_path(web)
    Medium.insert_all([ { file_path: web, media_type: "video", variants_status: "ready",
                          created_at: Time.current, updated_at: Time.current } ])
    files = Dir[File.join(VIDEO_DIR, "variants", "done-*")]
    past = Time.now - 3600
    files.each { |f| File.utime(past, past, f) }
    before = files.to_h { |f| [ f, [ File.mtime(f), File.size(f), File.read(f) ] ] }

    VideoVariantGenerator.stubs(:available?).returns(true)
    assert_no_enqueued_jobs(only: TranscodeVideoJob) do
      VideoVariantGenerator.status_for(Medium.find_by(file_path: web))
      VideoVariantGenerator.complete?(source)
      VideoRenderer.tag(web)
      VideoVariantGenerator.resume_interrupted!
      assert_not_includes VideoVariantGenerator.needing_optimization.map { |m| m.respond_to?(:file_path) ? m.file_path : m }, web
    end

    after = files.to_h { |f| [ f, [ File.mtime(f), File.size(f), File.read(f) ] ] }
    assert_equal before, after, "no variant or manifest touched"
  end
end
