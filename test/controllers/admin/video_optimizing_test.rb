require "test_helper"
require_relative "../../video_test_helpers"

# What the Media Browser shows about a video's web versions: the poster on
# its card, a progress bar while they're being made, the progress window's
# status endpoint, and the notice that stays until dismissed.
class Admin::VideoOptimizingTest < ActionDispatch::IntegrationTest
  include VideoTestHelpers

  setup do
    sign_in_as(users(:one))
    setup_video_dir
    # Progress lives in the cache (shared by the job and the web process);
    # the test environment's null store would drop it.
    @cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    VideoVariantGenerator.stubs(:available?).returns(true)
  end

  teardown do
    Rails.cache = @cache
    teardown_video_dir
  end

  def video_medium(name, status:)
    Medium.create!(file_path: "/media/video/#{name}", media_type: "video", uploaded_at: Time.current, variants_status: status)
  end

  test "status while optimizing: per-step progress from the running job" do
    web = fake_variants("busy.mov", renditions: [])
    manifest = VideoVariantGenerator.read_manifest(web).merge("complete" => false, "wanted" => %w[720p 1080p])
    File.write(VideoVariantGenerator.manifest_path(VideoVariantGenerator.normalize_path(web)), manifest.to_json)
    medium = video_medium("busy.mov", status: "processing")
    VideoVariantGenerator.write_progress(web, "720p", 46)

    get video_status_admin_medium_path(medium), headers: { "Accept" => "application/json" }
    status = JSON.parse(response.body)

    assert_equal "optimizing", status["state"]
    assert_equal %w[poster 720p 1080p], status["steps"].map { |s| s["name"] }
    assert_equal %w[done running waiting], status["steps"].map { |s| s["state"] }
    assert_equal 46, status["steps"][1]["percent"]
    assert_equal 23, status["percent"], "overall across the two renditions"
  end

  test "the card shows the poster and a progress bar while optimizing" do
    web = fake_variants("card.mp4", renditions: [])
    manifest = VideoVariantGenerator.read_manifest(web).merge("complete" => false, "wanted" => %w[720p])
    File.write(VideoVariantGenerator.manifest_path(VideoVariantGenerator.normalize_path(web)), manifest.to_json)
    medium = video_medium("card.mp4", status: "processing")
    VideoVariantGenerator.write_progress(web, "720p", 30)

    get card_admin_medium_path(medium), headers: { "Accept" => "application/json" }
    data = JSON.parse(response.body)

    assert data["pending"]
    assert_includes data["card_html"], %(src="/media/video/variants/card-poster.jpg")
    assert_includes data["card_html"], "optimizing 30%"
    assert_includes data["card_html"], 'data-variants-pending="true"'
    assert_not_includes data["card_html"], "🎬"
  end

  test "a finished video's card shows its poster, no bar" do
    fake_variants("shown.mp4")
    medium = video_medium("shown.mp4", status: "complete")

    get card_admin_medium_path(medium), headers: { "Accept" => "application/json" }
    data = JSON.parse(response.body)

    assert_not data["pending"]
    assert_includes data["card_html"], "shown-poster.jpg"
    assert_not_includes data["card_html"], "optimizing"
  end

  test "finished videos get a notice that stays until dismissed" do
    fake_variants("done.mov", renditions: %w[720p 1080p])
    video_medium("done.mov", status: "ready")

    get browse_admin_medium_index_path
    assert_select "#video-notices", text: /Video optimized/
    assert_select "#video-notices li", text: /done\.mov/

    get browse_admin_medium_index_path
    assert_select "#video-notices", 1, "still there on the next visit"

    post dismiss_video_notices_admin_medium_index_path
    follow_redirect!
    assert_select "#video-notices", 0
    assert_equal "complete", Medium.find_by(file_path: "/media/video/done.mov").variants_status
  end

  test "a failed video's notice says why" do
    fake_variants("broken.mov", renditions: [])
    video_medium("broken.mov", status: "processing")
    VideoVariantGenerator.record_failure("/media/video/broken.mov", "Not enough free disk space to make broken-720p.mp4.")

    get browse_admin_medium_index_path
    assert_select "#video-notices", text: /couldn't be optimized/
    assert_select "#video-notices", text: /Not enough free disk space/

    post dismiss_video_notices_admin_medium_index_path
    assert_equal "failed_seen", Medium.find_by(file_path: "/media/video/broken.mov").variants_status
  end

  test "the notice can be fetched on its own, for the page to swap in" do
    fake_variants("late.mov", renditions: %w[720p])
    video_medium("late.mov", status: "ready")

    get video_notices_admin_medium_index_path
    assert_response :success
    assert_select "#video-notices", text: /late\.mov/
    assert_select "#video-notices-slot", 0, "just the notice, not the page"

    Medium.find_by(file_path: "/media/video/late.mov").update!(variants_status: "complete")
    get video_notices_admin_medium_index_path
    assert_select "#video-notices", 0
  end

  test "the page includes the progress window" do
    get browse_admin_medium_index_path
    assert_select "[data-controller=video-progress] dialog[data-video-progress-target=dialog]"
    assert_select "[data-video-progress-target=footer]", text: /Feel free to close/
  end

  def optimizing_video(name, percent:)
    web = fake_variants(name, renditions: [])
    manifest = VideoVariantGenerator.read_manifest(web).merge("complete" => false, "wanted" => %w[720p])
    File.write(VideoVariantGenerator.manifest_path(VideoVariantGenerator.normalize_path(web)), manifest.to_json)
    VideoVariantGenerator.write_progress(web, "720p", percent)
    video_medium(name, status: "processing")
  end

  test "clicking an optimizing video's card reopens the progress window" do
    medium = optimizing_video("click.mp4", percent: 40)

    get browse_admin_medium_index_path
    assert_select "[data-action='click->media-upload#openFromCard'] [data-video-progress-id='#{medium.id}'][data-video-state=optimizing][data-video-progress-name='click.mp4']"
  end

  test "the editor's media picker shows the poster and progress, and is kept up to date" do
    medium = optimizing_video("picked.mp4", percent: 55)
    fake_variants("finished.mp4")
    video_medium("finished.mp4", status: "complete")

    get picker_admin_medium_index_path(media_type: "video")
    assert_response :success
    assert_select "[data-media-picker-target=optimizing][data-media-id='#{medium.id}']", 1
    assert_select "[data-media-picker-target=optimizing] img[src='/media/video/variants/picked-poster.jpg']"
    assert_select "[data-media-picker-target=optimizing]", text: /optimizing 55%/
    assert_select "img[src='/media/video/variants/finished-poster.jpg']", 1
    assert_no_match(/🎬/, response.body.scan(/<img[^>]*finished-poster[^>]*>/).join)

    get video_status_admin_medium_path(medium, thumbnail: 1, height: "h-24"), headers: { "Accept" => "application/json" }
    status = JSON.parse(response.body)
    assert_includes status["thumbnail_html"], "optimizing 55%"
    assert_includes status["thumbnail_html"], "h-24"
  end

  test "uploading a video says to open the progress window" do
    file = Tempfile.new([ "up", ".mp4" ])
    file.binmode
    file.write("v" * 100)
    file.rewind
    uploaded = Rack::Test::UploadedFile.new(file.path, "video/mp4", original_filename: "vo-upload.mp4")
    @made << "vo-upload.mp4"

    assert_enqueued_jobs 3, only: TranscodeVideoJob do
      post admin_medium_index_path, params: { files: [ uploaded ] }, headers: { "Accept" => "application/json" }
    end
    data = JSON.parse(response.body)
    assert data["success"], data.inspect
    assert data["video_optimizing"]
  ensure
    file&.close!
  end
end

# The status a video's Medium moves through as its jobs run.
class VideoVariantStatusFlowTest < ActiveSupport::TestCase
  include VideoTestHelpers

  setup { setup_video_dir }
  teardown { teardown_video_dir }

  test "processing → ready when the last file is made, and a later run doesn't bring the notice back" do
    web = make_clip("flow.mp4", size: "640x360", bitrate: "3M")
    medium = Medium.create!(file_path: web, media_type: "video", uploaded_at: Time.current, variants_status: "pending")

    VideoVariantGenerator.generate(web, "poster")
    assert_equal "processing", medium.reload.variants_status

    VideoVariantGenerator.generate(web, "720p")
    assert_equal "ready", medium.reload.variants_status

    VideoVariantGenerator.dismiss_notices!
    VideoVariantGenerator.generate(web, "1080p") # not needed for 360p, finds nothing to do
    assert_equal "complete", medium.reload.variants_status
  end

  test "progress is reported while a rendition encodes" do
    web = make_clip("progress.mp4", size: "640x360", seconds: 4, bitrate: "3M")
    seen = []
    VideoVariantGenerator.stubs(:write_progress).with { |_w, step, pct| seen << [ step, pct ] if step == "720p"; true }

    VideoVariantGenerator.generate(web, "720p")
    assert seen.any?, "write_progress was called"
    assert_equal 0, seen.first[1]
  end
end
