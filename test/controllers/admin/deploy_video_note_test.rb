# frozen_string_literal: true

require "test_helper"

# A note above Deploy while a video is being optimized. Kamal builds Roe on
# this computer, so a deploy then competes with ffmpeg for it; Fly builds in
# the cloud, so it's only a reminder that the video reaches live through
# Site Sync. Either way Deploy stays available.
class Admin::DeployVideoNoteTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    Admin::UpdatesController.any_instance.stubs(:deploy_prerequisites).returns([])
    DeployConfigGenerator.stubs(:kamal_cli_available?).returns(true)
    DeployConfigGenerator.stubs(:fly_cli_available?).returns(true)

    @deploy_file = SiteConfig::DEPLOY_FILE
    @saved = File.exist?(@deploy_file) ? File.read(@deploy_file) : nil
  end

  teardown do
    @saved ? File.write(@deploy_file, @saved) : FileUtils.rm_f(@deploy_file)
  end

  def deploy_target(target)
    FileUtils.mkdir_p(File.dirname(@deploy_file))
    File.write(@deploy_file, "target: #{target}\n")
  end

  def optimizing(*paths)
    VideoVariantGenerator.stubs(:optimizing_now).returns(paths.map { |p| Medium.new(file_path: p, media_type: "video") })
  end

  test "nothing being optimized: no note" do
    optimizing
    get admin_updates_path

    assert_response :success
    assert_select "[data-deploy-video-note]", false
    assert_select "button[data-deploy-url]"
  end

  test "with Kamal: says to wait, and why, and Deploy stays" do
    deploy_target("kamal")
    optimizing("/media/video/clip.mp4")
    get admin_updates_path

    assert_select "[data-deploy-video-note]" do
      assert_select "*", text: /A video is being optimized/
      assert_select "span", text: "clip.mp4"
      assert_select "*", text: /builds Roe on this computer/
    end
    assert_select "button[data-deploy-url]", 1, "the note mustn't take Deploy away"
    assert_match "Kamal builds on this computer", response.body
  end

  test "with Fly: deploying is fine, the video comes with Site Sync" do
    deploy_target("fly")
    optimizing("/media/video/a.mp4", "/media/video/b.mp4", "/media/video/c.mp4", "/media/video/d.mp4")
    get admin_updates_path

    assert_select "[data-deploy-video-note]" do
      assert_select "*", text: /4 videos are being optimized/
      assert_select "span", text: "a.mp4, b.mp4, c.mp4 and 1 more"
      assert_select "*", text: /Fly builds in the cloud/
    end
  end

  test "optimizing_now: a video with a job, or fresh progress, and no others" do
    queued = Medium.create!(file_path: "/media/video/queued.mp4", media_type: "video")
    encoding = Medium.create!(file_path: "/media/video/encoding.mp4", media_type: "video")
    Medium.create!(file_path: "/media/video/idle.mp4", media_type: "video")

    VideoVariantGenerator.stubs(:videos_with_jobs).returns(Set[queued.file_path])
    VideoVariantGenerator.stubs(:live_progress).returns(nil)
    VideoVariantGenerator.stubs(:live_progress).with(encoding.file_path).returns({ percent: 40 })

    assert_equal %w[/media/video/encoding.mp4 /media/video/queued.mp4],
                 VideoVariantGenerator.optimizing_now.map(&:file_path).sort
  end
end
