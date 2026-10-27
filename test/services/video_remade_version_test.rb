# frozen_string_literal: true

require "test_helper"
require_relative "../video_test_helpers"

# Deleting one of a finished video's web versions — the 1080p, say — and
# making it again with OPTIMIZE VIDEOS. The manifest still listed the
# deleted file, so the progress window and the card showed it as done, and
# the first job to finish (the poster, still there) marked the whole video
# ready while the 1080p was still being made: no progress, and the card's
# watch stopped.
class VideoRemadeVersionTest < ActiveSupport::TestCase
  include VideoTestHelpers

  VVG = VideoVariantGenerator

  setup do
    setup_video_dir
    @cache = ActiveSupport::Cache::MemoryStore.new
    Rails.stubs(:cache).returns(@cache)
    VVG.stubs(:available?).returns(true)

    @web = fake_variants("zz-remade.mp4", renditions: %w[720p 1080p])
    @source = File.join(RoeSitePaths::SITE_PATH, @web.delete_prefix("/"))
    path = VVG.manifest_path(@source)
    File.write(path, JSON.parse(File.read(path)).merge("wanted" => %w[720p 1080p]).to_json)
    Medium.create!(file_path: @web, media_type: "video")
    Medium.where(file_path: @web).update_all(variants_status: "complete")

    File.delete(VVG.variant_path_for(@source, "1080p"))
  end

  teardown do
    teardown_video_dir
    Medium.where(file_path: @web).delete_all
  end

  def status = VVG.status_for(Medium.find_by(file_path: @web))
  def step(name) = status[:steps].find { |s| s[:name] == name }

  # What finish does after a job: the manifest copy the job read, as written.
  def job_finishes(name)
    VVG.send(:finish, @source, VVG.current_manifest(@source), %w[720p 1080p], name)
  end

  test "a deleted version shows as still to do, not done" do
    assert_equal "none", status[:state], "OPTIMIZE VIDEOS offers it"
    assert_equal "done", step("720p")[:state]
    assert_equal "waiting", step("1080p")[:state]
    assert_equal [ "720p" ], status[:outputs].map { |o| o["name"] }
  end

  test "while it's made again, the window shows what's there and what's being made" do
    Medium.where(file_path: @web).update_all(variants_status: "queued")
    VVG.write_progress(@web, "1080p", 40)

    assert_equal "optimizing", status[:state]
    assert_equal "done", step("poster")[:state]
    assert_equal "done", step("720p")[:state]
    assert_equal "running", step("1080p")[:state]
    assert_equal 40, step("1080p")[:percent]
    assert_equal 70, status[:percent], "720p done, 1080p at 40%"
  end

  test "the poster and 720p jobs finding nothing to do don't mark it ready" do
    Medium.where(file_path: @web).update_all(variants_status: "queued")

    job_finishes("poster")
    job_finishes("720p")

    assert_equal "processing", Medium.find_by(file_path: @web).variants_status
    assert_equal "optimizing", status[:state], "the card keeps watching"
    assert_not VVG.read_manifest(@source)["complete"]
    assert_equal [ "720p" ], VVG.read_manifest(@source)["variants"].map { |r| r["name"] }
  end

  test "once the 1080p is made again it's ready" do
    Medium.where(file_path: @web).update_all(variants_status: "processing")
    File.binwrite(VVG.variant_path_for(@source, "1080p"), "v")
    mine = VVG.current_manifest(@source)
    mine["variants"] << { "name" => "1080p", "path" => "/media/video/variants/zz-remade-1080p.mp4", "size" => 1 }

    VVG.send(:finish, @source, mine, %w[720p 1080p], "1080p")

    assert_equal "ready", Medium.find_by(file_path: @web).variants_status
    assert_equal "done", status[:state]
  end

  test "a deleted poster is made again too" do
    File.delete(VVG.variant_path_for(@source, "poster"))

    assert_equal "waiting", step("poster")[:state]
    assert_nil status[:poster], "no broken thumbnail"
  end
end
