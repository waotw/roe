require "test_helper"
require_relative "../video_test_helpers"

# A video copied straight into site/media (Finder, Site Sync) is seen
# before it's fully written. The job must wait and try again rather than
# fail, and the video must keep showing as optimizing while it waits.
class TranscodeVideoJobRetryTest < ActiveJob::TestCase
  include VideoTestHelpers

  setup { setup_video_dir }
  teardown { teardown_video_dir }

  test "a file still being copied in is retried later, not failed" do
    web = fake_variants("copying.mp4", renditions: [], poster: false)
    File.delete(VideoVariantGenerator.manifest_path(VideoVariantGenerator.normalize_path(web)))
    medium = Medium.create!(file_path: web, media_type: "video", uploaded_at: Time.current, variants_status: "queued")
    VideoVariantGenerator.stubs(:available?).returns(true)
    VideoVariantGenerator.stubs(:still_arriving?).returns(true)

    assert_enqueued_with(job: TranscodeVideoJob, args: [ web, "poster", false ]) do
      TranscodeVideoJob.perform_now(web, "poster", false)
    end

    assert_equal "queued", medium.reload.variants_status, "not marked failed"
    assert_nil VideoVariantGenerator.last_error(web)
    assert_equal "optimizing", VideoVariantGenerator.status_for(medium)[:state]
  end

  test "once the copy has finished, the retried job makes the file" do
    web = make_clip("settled.mp4", size: "640x360", bitrate: "3M")
    Medium.create!(file_path: web, media_type: "video", uploaded_at: Time.current, variants_status: "queued")

    VideoVariantGenerator.stubs(:still_arriving?).returns(true)
    TranscodeVideoJob.perform_now(web, "poster", false)
    assert_nil VideoVariantGenerator.read_manifest(web)

    VideoVariantGenerator.unstub(:still_arriving?)
    TranscodeVideoJob.perform_now(web, "poster", false)
    assert VideoVariantGenerator.read_manifest(web)["poster"].present?
  end

  # What happened to three-benches: the 1080p job (slow) read the manifest
  # before the 720p job (fast) wrote its entry, then wrote its own copy
  # back and erased it. The 720p file was on disk, but the manifest forgot
  # it, and the video sat at "optimizing 50%" for good.
  test "a slow job finishing last doesn't erase what a faster one recorded" do
    web = make_clip("race.mp4", size: "1280x720", seconds: 2, bitrate: "6M")
    VideoVariantGenerator.generate(web, "poster")
    source = VideoVariantGenerator.normalize_path(web)

    # The slow job takes its copy of the manifest now...
    slow_copy = VideoVariantGenerator.current_manifest(source).deep_dup
    # ...the fast job makes 720p and records it...
    VideoVariantGenerator.generate(web, "720p")
    assert_includes VideoVariantGenerator.current_manifest(source)["variants"].map { |r| r["name"] }, "720p"

    # ...then the slow job finishes with its stale copy.
    File.binwrite(VideoVariantGenerator.variant_path_for(source, "1080p"), "v")
    slow_copy["variants"] << { "name" => "1080p", "path" => "/media/video/variants/race-1080p.mp4", "size" => 1 }
    VideoVariantGenerator.send(:finish, source, slow_copy, %w[720p 1080p], "1080p")

    names = VideoVariantGenerator.current_manifest(source)["variants"].map { |r| r["name"] }
    assert_equal %w[720p 1080p], names
    assert VideoVariantGenerator.current_manifest(source)["poster"].present?
  end

  test "a second transcode steps back while one is running, instead of running alongside" do
    web = make_clip("busy-lock.mp4", size: "320x240")

    VideoVariantGenerator.send(:with_transcode_lock) do
      assert_raises(VideoVariantGenerator::Busy) { VideoVariantGenerator.generate(web, "poster") }
      assert_enqueued_with(job: TranscodeVideoJob, args: [ web, "poster", false ]) do
        TranscodeVideoJob.perform_now(web, "poster", false)
      end
    end

    assert VideoVariantGenerator.generate(web, "poster"), "runs once the other has finished"
  end
end
