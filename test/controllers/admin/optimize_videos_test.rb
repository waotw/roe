require "test_helper"
require_relative "../../video_test_helpers"

# OPTIMIZE VIDEOS on the Media Browser: for videos added before ffmpeg was
# installed (or brought in by Site Sync), and for ones that failed. Shown
# only when there's something to do and ffmpeg is here to do it.
class Admin::OptimizeVideosTest < ActionDispatch::IntegrationTest
  include VideoTestHelpers
  include ActiveJob::TestHelper

  setup do
    sign_in_as(users(:one))
    setup_video_dir
    @cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    VideoVariantGenerator.stubs(:available?).returns(true)
  end

  teardown do
    Rails.cache = @cache
    teardown_video_dir
  end

  # A video on disk with a Medium row and no web versions, as if added
  # before ffmpeg was installed. Medium's after_create would queue it (ffmpeg
  # is stubbed in), so the row is inserted without callbacks.
  def plain_video(name, status: "pending")
    File.binwrite(File.join(VIDEO_DIR, name), "v" * 500)
    @made << name
    Medium.insert_all([ { file_path: "/media/video/#{name}", media_type: "video", uploaded_at: Time.current,
                          variants_status: status, created_at: Time.current, updated_at: Time.current } ])
    Medium.find_by!(file_path: "/media/video/#{name}")
  end

  def button = "form[action='#{optimize_videos_admin_medium_index_path}'] button"

  test "the button counts videos with no web versions and ones that failed — not finished or busy ones" do
    plain_video("never.mp4")
    failed = plain_video("broke.mp4")
    VideoVariantGenerator.record_failure(failed.file_path, "Not enough free disk space.")
    plain_video("busy.mp4", status: "processing")
    Rails.cache.write(VideoVariantGenerator.queue_cache_key("/media/video/busy.mp4"), true) # its jobs are queued
    fake_variants("done.mp4")
    Medium.create!(file_path: "/media/video/done.mp4", media_type: "video", uploaded_at: Time.current, variants_status: "complete")

    get browse_admin_medium_index_path
    assert_select button, text: "OPTIMIZE VIDEOS (2)"
  end

  # three-benches: marked "processing", its 1080p made, but the manifest
  # lost the 720p and nothing was left running — stuck at 50% for good.
  test "a video stuck mid-way, with nothing running, is counted and requeued" do
    web = fake_variants("stuck.mp4", renditions: %w[1080p])
    path = VideoVariantGenerator.normalize_path(web)
    manifest = VideoVariantGenerator.read_manifest(web).merge("complete" => false, "wanted" => %w[720p 1080p])
    File.write(VideoVariantGenerator.manifest_path(path), manifest.to_json)
    medium = Medium.find_by(file_path: web) ||
             Medium.insert_all([ { file_path: web, media_type: "video", variants_status: "processing", created_at: Time.current, updated_at: Time.current } ]) &&
             Medium.find_by!(file_path: web)
    medium.update_columns(variants_status: "processing")

    get browse_admin_medium_index_path
    assert_select button, text: "OPTIMIZE VIDEOS (1)"

    assert_enqueued_jobs 3, only: TranscodeVideoJob do
      post optimize_videos_admin_medium_index_path
    end
    assert_equal "queued", medium.reload.variants_status
  end

  test "it sits below PRUNE VARIANTS" do
    plain_video("order.mp4")

    get browse_admin_medium_index_path
    html = response.body
    assert_operator html.index("PRUNE VARIANTS"), :<, html.index("OPTIMIZE VIDEOS")
  end

  test "hidden when nothing needs it" do
    fake_variants("fine.mp4")
    Medium.create!(file_path: "/media/video/fine.mp4", media_type: "video", uploaded_at: Time.current, variants_status: "complete")

    get browse_admin_medium_index_path
    assert_select button, 0
  end

  test "hidden without ffmpeg, and refuses to run" do
    VideoVariantGenerator.stubs(:available?).returns(false)
    plain_video("nofx.mp4")

    get browse_admin_medium_index_path
    assert_select button, 0

    assert_no_enqueued_jobs { post optimize_videos_admin_medium_index_path }
    assert_match(/isn't installed/, flash[:alert])
  end

  test "queues each one — retrying failures — and says so" do
    plain_video("one.mp4")
    failed = plain_video("two.mov")
    VideoVariantGenerator.record_failure(failed.file_path, "Couldn't make two-720p.mp4.")

    assert_enqueued_jobs 6, only: TranscodeVideoJob do # 2 videos × poster + 720p + 1080p
      post optimize_videos_admin_medium_index_path
    end
    assert_redirected_to browse_admin_medium_index_path
    assert_match(/Optimizing 2 videos/, flash[:notice])

    assert_equal "queued", failed.reload.variants_status
    assert_nil VideoVariantGenerator.last_error(failed.file_path), "the old error is cleared"
    assert_equal "optimizing", VideoVariantGenerator.status_for(failed)[:state]

    follow_redirect!
    assert_select button, 0, "nothing left to optimize while they're queued"
  end

  test "nothing to do says so" do
    post optimize_videos_admin_medium_index_path
    assert_match(/already optimized/, flash[:notice])
  end

  # Ben's test: delete a video's web versions by hand. The database still
  # says "complete", but the files decide — it's offered again.
  test "a finished video whose web versions were deleted is offered again" do
    web = fake_variants("deleted.mp4", renditions: %w[720p])
    Medium.insert_all([ { file_path: web, media_type: "video", variants_status: "complete",
                          created_at: Time.current, updated_at: Time.current } ])
    medium = Medium.find_by!(file_path: web)
    assert_equal "done", VideoVariantGenerator.status_for(medium)[:state]

    VideoVariantGenerator.delete_variants(VideoVariantGenerator.normalize_path(web))
    assert_equal "none", VideoVariantGenerator.status_for(medium)[:state]

    get browse_admin_medium_index_path
    assert_select button, text: "OPTIMIZE VIDEOS (1)"
  end

  test "deleting just one rendition counts too" do
    web = fake_variants("partial.mp4", renditions: %w[720p 1080p])
    Medium.insert_all([ { file_path: web, media_type: "video", variants_status: "complete",
                          created_at: Time.current, updated_at: Time.current } ])
    File.delete(VideoVariantGenerator.variant_path_for(VideoVariantGenerator.normalize_path(web), "1080p"))

    get browse_admin_medium_index_path
    assert_select button, text: "OPTIMIZE VIDEOS (1)"
  end
end
