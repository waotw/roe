# frozen_string_literal: true

require "test_helper"
require "open3"

# bin/roe-logs (`roe logs`): a short report of what went wrong recently, read
# from the log files without loading Rails. Run here the way the CLI runs it,
# against log files written for each test, with the clock pinned.
class RoeLogsTest < ActiveSupport::TestCase
  NOW = "2026-10-13 15:30:00 -0500"

  setup do
    @dir = Dir.mktmpdir("roe-logs")
    @app = File.join(@dir, "current")
    FileUtils.mkdir_p([ File.join(@app, "bin"), File.join(@app, "log") ])
    FileUtils.cp(Rails.root.join("bin/roe-logs"), File.join(@app, "bin"))
    File.write(File.join(@app, "VERSION"), "---\nversion: 0.4.0-nightly.9\n")
  end

  teardown { FileUtils.rm_rf(@dir) }

  def rails_log(text) = File.write(File.join(@app, "log/development.log"), text)
  def daemon_log(text) = File.write(File.join(@app, "log/roe-daemon.log"), text)

  def report(*flags, pid: "4242")
    env = { "ROE_LOGS_NOW" => NOW, "ROE_LOGS_SITE" => "my-site", "ROE_LOGS_PID" => pid, "ROE_LOGS_PORT" => "3000" }
    out, err, status = Open3.capture3(env, RbConfig.ruby, File.join(@app, "bin/roe-logs"), *flags)
    assert status.success?, err
    out
  end

  def request(at, path, lines = [])
    [ %(Started GET "#{path}" for 127.0.0.1 at #{at}), *lines, "" ].join("\n")
  end

  PAGE_500 = [
    "  Rendered layout layouts/site.html.erb (Duration: 16.4ms | GC: 1.9ms)",
    "Completed 500 Internal Server Error in 269ms (ActiveRecord: 2.8ms)",
    "",
    "ActionView::Template::Error (undefined method 'authenticated?' for nil)",
    "Caused by: NoMethodError (undefined method 'authenticated?' for nil)",
    "",
    "Information for: ActionView::Template::Error (undefined method 'authenticated?' for nil):",
    "    423:   var IS_ADMIN = <%= authenticated? %>;",
    "app/views/layouts/site.html.erb:424",
    "app/controllers/posts_controller.rb:12:in 'PostsController#show'"
  ].freeze

  test "a failed page: the request, the error, and the lines of Roe it went through" do
    rails_log(request("2026-10-13 15:10:00 -0500", "/posts/hello", PAGE_500))

    out = report

    assert_includes out, "ROE LOGS my-site · the last hour"
    assert_includes out, "VERSION: 0.4.0-nightly.9"
    assert_includes out, "SERVER:  running on port 3000"
    assert_includes out, "15:10  Page failed (500)  GET /posts/hello"
    assert_includes out, "ActionView::Template::Error: undefined method 'authenticated?' for nil"
    assert_includes out, "app/views/layouts/site.html.erb:424"
    assert_not_includes out, "Rendered layout", "ordinary lines stay out"
  end

  test "older than the window isn't shown; --2h and --day reach further" do
    rails_log(request("2026-10-13 13:45:00 -0500", "/old", PAGE_500) + request("2026-10-13 15:20:00 -0500", "/fine"))

    assert_includes report, "ERRORS  none in the last hour"
    assert_includes report("--2h"), "GET /old"
    assert_includes report("--day"), "GET /old"
  end

  test "a day's window gives the date for yesterday's errors" do
    rails_log(request("2026-10-12 18:03:00 -0500", "/yesterday", PAGE_500))

    assert_includes report("--day"), "Oct 12 18:03  Page failed (500)"
  end

  test "a failed job, the same failure repeated as one entry, and a job that gave up" do
    job = lambda do |at, id|
      [
        %([ActiveJob] [TranscodeVideoJob] [#{id}] Performing TranscodeVideoJob (Job ID: #{id}) from SolidQueue(video) enqueued at #{at} with arguments: "/media/video/a.mp4"),
        %([ActiveJob] [TranscodeVideoJob] [#{id}] Error performing TranscodeVideoJob (Job ID: #{id}) from SolidQueue(video) in 12.5ms: Errno::ENOENT (No such file or directory - a.mp4):),
        "app/services/video_variant_generator.rb:615:in 'File.size'",
        "app/jobs/transcode_video_job.rb:42:in 'TranscodeVideoJob#perform'",
        ""
      ].join("\n")
    end
    rails_log(
      job.call("2026-10-13T20:05:00.000000000Z", "aaaaaaaa-1111-2222-3333-444444444444") +
      job.call("2026-10-13T20:15:00.000000000Z", "bbbbbbbb-1111-2222-3333-444444444444") +
      "[ActiveJob] [TranscodeVideoJob] [cccccccc-1111-2222-3333-444444444444] Discarded TranscodeVideoJob (Job ID: cccccccc-1111-2222-3333-444444444444) due to a VideoVariantGenerator::Error (a.mp4 isn't there any more).\n"
    )

    out = report

    assert_includes out, "15:15  Job failed: TranscodeVideoJob"
    assert_includes out, "Errno::ENOENT: No such file or directory - a.mp4"
    assert_includes out, "app/jobs/transcode_video_job.rb:42"
    assert_includes out, "×2 since 15:05"
    assert_includes out, "Job gave up: TranscodeVideoJob"
  end

  test "Roe's own failure notes are listed, without repeating an error already shown" do
    rails_log(request("2026-10-13 15:00:00 -0500", "/admin/sync", [
      "[SiteSync::Exchange] peer call failed: Net::OpenTimeout",
      "[SiteSync::Exchange] peer call failed: Net::OpenTimeout",
      "  Medium Update All (0.1ms)  UPDATE \"media\" SET \"variants_status\" = 'failed'",
      "[SubstackImporter] Stats: {posts_created: 0, errors: []}",
      "[ContentSync] Synced 12 posts"
    ]))

    out = report

    assert_includes out, "ALSO LOGGED"
    assert_match(/\[SiteSync::Exchange\] peer call failed: Net::OpenTimeout\s+×2/, out)
    assert_not_includes out, "Medium Update All", "a database line that mentions failure"
    assert_not_includes out, "SubstackImporter", "errors: [] means none"
    assert_not_includes out, "Synced 12 posts"
  end

  test "server not running: why its last start didn't finish" do
    rails_log("")
    daemon_log(<<~LOG)
      ==> Roe starting 2026-10-13 14:00:00 -0500
      => Booting Puma
      * Listening on http://127.0.0.1:3000
      Use Ctrl-C to stop
      Exiting

      ==> Roe starting 2026-10-13 15:20:00 -0500
      => Booting Puma
        SolidCache::Entry Load (0.1ms)  SELECT 1
      Exiting
      config/initializers/foo.rb:3:in '<main>': undefined local variable or method 'bar' for main (NameError)
    LOG

    out = report(pid: "")

    assert_includes out, "SERVER:  not running"
    assert_includes out, "LAST START (Oct 13 15:20)  it didn't finish starting"
    assert_includes out, "undefined local variable or method 'bar' for main (NameError)"
    assert_not_includes out, "SolidCache", "database lines left out"
  end

  test "while the server runs, its last start isn't shown" do
    rails_log("")
    daemon_log("==> Roe starting 2026-10-13 15:00:00 -0500\nUse Ctrl-C to stop\n")

    out = report

    assert_includes out, "SERVER:  running on port 3000 · started Oct 13 15:00"
    assert_not_includes out, "LAST START"
  end

  test "email addresses, keys and the home folder are blanked out" do
    rails_log(request("2026-10-13 15:10:00 -0500", "/members/signin?token=abc123", [
      "[MemberMailer] couldn't send to reader@example.com with key sk_test_51AbCdEfGhIjKl from #{Dir.home}/roe/site"
    ]))

    out = report

    assert_includes out, "[email]"
    assert_includes out, "[key]"
    assert_includes out, "~/roe/site"
    assert_not_includes out, "reader@example.com"
    assert_not_includes out, "sk_test_51AbCdEfGhIjKl"
    assert_not_includes out, Dir.home
  end

  test "an unknown flag is refused" do
    _out, err, status = Open3.capture3({ "ROE_LOGS_NOW" => NOW }, RbConfig.ruby, File.join(@app, "bin/roe-logs"), "--week")

    assert_not status.success?
    assert_includes err, "Use --2h or --day"
  end
end
