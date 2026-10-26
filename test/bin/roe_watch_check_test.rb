# frozen_string_literal: true

require "test_helper"
require "open3"

# bin/roe-watch-check (`roe status`): finds a content file changed since the
# ContentWatcher last heard anything — the sign it's stopped picking up
# changes. Run here the way roe.sh runs it, against a site built per test.
class RoeWatchCheckTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir("roe-watch-check")
    @app = File.join(@dir, "current")
    @site = File.join(@dir, "site")
    FileUtils.mkdir_p([ File.join(@app, "bin"), File.join(@app, "tmp") ])
    FileUtils.cp(Rails.root.join("bin/roe-watch-check"), File.join(@app, "bin"))
    @seen = File.join(@app, "tmp/content_watcher.seen")
  end

  teardown { FileUtils.rm_rf(@dir) }

  def file(rel, at:)
    path = File.join(@site, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "x")
    File.utime(at, at, path)
  end

  def seen(at:)
    FileUtils.touch(@seen)
    File.utime(at, at, @seen)
  end

  def check
    out, err, status = Open3.capture3(RbConfig.ruby, File.join(@app, "bin/roe-watch-check"), @site)
    assert_empty err
    [ status.exitstatus, out ]
  end

  test "a file changed after the watcher last heard anything is reported" do
    seen(at: Time.now - 3600)
    file("documentation/roe/integrations_postmark.md", at: Time.now - 120)
    file("posts/old.md", at: Time.now - 7200)

    code, out = check

    assert_equal 1, code
    assert_includes out, "documentation/roe/integrations_postmark.md (#{(Time.now - 120).strftime('%H:%M')})"
    assert_includes out, "Last change it picked up:"
    assert_not_includes out, "posts/old.md", "changed before the mark: the watcher saw it"
  end

  test "nothing changed since: silent" do
    seen(at: Time.now - 60)
    file("posts/a.md", at: Time.now - 3600)

    assert_equal [ 0, "" ], check
  end

  test "a save from the last few seconds is still being handled, not missed" do
    seen(at: Time.now - 3600)
    file("posts/just-saved.md", at: Time.now - 2)

    assert_equal [ 0, "" ], check
  end

  test "files the watcher never hears about don't count" do
    seen(at: Time.now - 3600)
    recent = Time.now - 120
    file("media/variants/clip-720p.mp4", at: recent)
    file("media/.DS_Store", at: recent)
    file("posts/.hidden/draft.md", at: recent)
    file("posts/draft.md.swp", at: recent)
    file("posts/draft.md~", at: recent)
    file("db/development.sqlite3", at: recent) # not a watched folder

    assert_equal [ 0, "" ], check
  end

  test "no mark yet (an older server, or tmp/ cleared): no way to tell, so silent" do
    file("posts/a.md", at: Time.now - 120)

    assert_equal [ 0, "" ], check
  end

  test "many missed: the newest three, then a count" do
    seen(at: Time.now - 3600)
    5.times { |i| file("posts/p#{i}.md", at: Time.now - 100 - i * 60) }

    _, out = check

    assert_match %r{posts/p0\.md .*posts/p1\.md .*posts/p2\.md .*, and 2 more}, out
  end

  test "watches the same folders as ContentWatcher" do
    script = File.read(Rails.root.join("bin/roe-watch-check"))
    listed = script[/WATCHED = %w\[([^\]]+)\]/, 1].split
    assert_equal ContentWatcher::WATCH_PATHS.map { |p| File.basename(p) }.sort, listed.sort
  end

  test "ContentWatcher leaves the mark when it hears a change, before handling it" do
    FileUtils.rm_f(ContentWatcher::SEEN_FILE)
    ContentWatcher.stubs(:detect_renames).raises(RuntimeError, "boom")

    assert_raises(RuntimeError) { ContentWatcher.send(:handle_changes, [], [], []) }
    assert File.exist?(ContentWatcher::SEEN_FILE), "marked even though handling failed"
  ensure
    FileUtils.rm_f(ContentWatcher::SEEN_FILE)
  end
end
