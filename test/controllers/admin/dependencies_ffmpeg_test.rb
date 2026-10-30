require "test_helper"

# The Tools pages for optional external tools: Images & Video (libvips,
# ffmpeg) and Developer Tools (Stripe CLI). Each missing tool points at
# `roe install <tool>` and lists the ways it can go on this computer, with
# the reason any are skipped. ffmpeg says which half is missing when only
# one of ffmpeg / ffprobe is found.
class Admin::DependenciesFfmpegTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    ManagedTools::Platform.bottle_cache.clear
  end

  def stub_ffmpeg(ffmpeg: nil, ffprobe: nil)
    ManagedTools::Ffmpeg.any_instance.stubs(:ffmpeg_path).returns(ffmpeg)
    ManagedTools::Ffmpeg.any_instance.stubs(:ffprobe_path).returns(ffprobe)
  end

  test "Images & Video lists libvips and ffmpeg, not the Stripe CLI" do
    stub_ffmpeg

    get admin_dependencies_path
    assert_response :success
    assert_match(/Images &amp; Video/, response.body)
    assert_match(/>\s*libvips\s*</, response.body)
    assert_match(/>\s*ffmpeg\s*</, response.body)
    assert_match(/Video conversion tool/, response.body)
    assert_match(/roe install ffmpeg/, response.body)
    assert_match(/Direct download/, response.body)
    assert_no_match(/Stripe CLI/, response.body)
    assert_no_match(/Found ffmpeg but not ffprobe/, response.body)
  end

  test "a Homebrew that can't build for this macOS is shown as skipped, with why" do
    stub_ffmpeg
    ManagedTools::Platform.any_instance.stubs(:package_manager).returns(:brew)
    ManagedTools::Platform.any_instance.stubs(:os).returns(:macos)
    ManagedTools::Platform.any_instance.stubs(:os_version).returns("14.8.5")
    ManagedTools::Platform.any_instance.stubs(:homebrew_bottle?).returns(false)

    get admin_dependencies_path
    assert_match(/no longer has ready-made builds for macOS 14/, response.body)
    assert_match(/roe install ffmpeg/, response.body)
  end

  test "Developer Tools lists only the Stripe CLI, and re-checks itself" do
    ManagedTools::Platform.stubs(:command_available?).returns(false)

    get admin_development_dependencies_path
    assert_response :success
    assert_match(/Developer Tools/, response.body)
    assert_match(/Stripe CLI/, response.body)
    assert_no_match(/>\s*ffmpeg\s*</, response.body)
    assert_no_match(/>\s*libvips\s*</, response.body)
    assert_select "a[href=?]", admin_development_dependencies_path, text: /re-check/
  end

  test "says ffprobe is missing when only ffmpeg is found" do
    stub_ffmpeg(ffmpeg: "/x/ffmpeg")

    get admin_dependencies_path
    assert_match(/Found ffmpeg but not ffprobe/, response.body)
  end

  test "every tool is on exactly one Tools page" do
    media = ManagedTools.statuses(group: :media).map { |s| s[:key] }
    development = ManagedTools.statuses(group: :development).map { |s| s[:key] }

    assert_equal %i[libvips ffmpeg], media
    assert_equal %i[stripe], development
    assert_equal ManagedTools.all.map(&:key).sort, (media + development).sort
  end
end

# The rake tasks bin/roe reads: tab-separated, "-" for an empty field so
# bash's `read` keeps the columns lined up.
require "rake"

class ManagedToolsRakeTasksTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("roe:tools:methods")
    ManagedTools::Platform.bottle_cache.clear
    ManagedTools::Ffmpeg.any_instance.stubs(:installed?).returns(false)
    ManagedTools::Platform.stubs(:mise_path).returns("/x/mise")
  end

  def run_task(name, *args)
    task = Rake::Task[name]
    task.reenable
    out, = capture_io { task.invoke(*args) }
    out
  end

  test "roe:tools:methods prints the tool line, then each method with no empty fields" do
    lines = run_task("roe:tools:methods", "ffmpeg").lines.map { |l| l.chomp.split("\t", -1) }

    assert_equal "tool", lines.first[0]
    assert_equal %w[ffmpeg ffmpeg no], lines.first[1, 3]
    methods = lines.drop(1)
    assert_equal %w[package_manager download mise], methods.map { |m| m[1] }
    methods.each do |m|
      assert_equal 9, m.size, m.inspect
      assert m.none?(&:empty?), "empty field in #{m.inspect}"
    end
  end

  test "roe:tools:check reports the state in three fields" do
    out = run_task("roe:tools:check", "ffmpeg").chomp.split("\t", -1)
    assert_equal 3, out.size
    assert_equal "no", out[0]
  end
end
