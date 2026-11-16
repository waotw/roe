# frozen_string_literal: true

require "test_helper"

# What happens when loading a changed file goes wrong. Before, the first
# error ended the batch (the other files in it never loaded) and the listen
# gem wrote it only to the background log, where nobody saw it. Most of the
# logged errors were one bug: a deleted media file's address was worked out
# with File.realpath, which fails on a file that's gone.
class ContentWatcherErrorsTest < ActiveSupport::TestCase
  setup do
    FileUtils.rm_f(ContentWatcher::ERRORS_FILE)
    ContentWatcher.stubs(:trigger_static_generation)
    ContentWatcher.stubs(:mark_seen)
    @files = []
  end

  teardown do
    FileUtils.rm_f(ContentWatcher::ERRORS_FILE)
    @files.each { |f| FileUtils.rm_f(f) }
  end

  def site(rel) = File.join(RoeSitePaths::SITE_PATH, rel)

  test "a deleted media file's record is removed (it used to raise ENOENT)" do
    rel = "/media/images/zz-watcher-gone-#{SecureRandom.hex(4)}.png"
    Medium.create!(file_path: rel, media_type: "png", uploaded_at: Time.current)
    assert_not File.exist?(site(rel))

    ContentWatcher.send(:handle_changes, [], [], [ site(rel) ])

    assert_not Medium.exists?(file_path: rel)
    assert_empty ContentWatcher.watcher_errors
  end

  test "one file that fails doesn't stop the rest of the batch, and is recorded for roe status" do
    bad = site("posts/zz-watcher-bad.md")
    good = site("posts/zz-watcher-good.md")
    loaded = []
    ContentWatcher.stubs(:process_file).with { |f| loaded << f; true }.returns(nil)
    ContentWatcher.stubs(:process_file).with(bad).raises(NoMethodError, "undefined method 'x'")

    ContentWatcher.send(:handle_changes, [ bad, good ], [], [])

    assert_includes loaded, good
    errors = ContentWatcher.watcher_errors
    assert_equal [ "posts/zz-watcher-bad.md" ], errors.keys
    assert_match "NoMethodError: undefined method 'x'", errors["posts/zz-watcher-bad.md"]["error"]
  end

  test "a later load that works clears the file's error" do
    bad = site("posts/zz-watcher-bad.md")
    ContentWatcher.stubs(:process_file).raises(RuntimeError, "boom")
    ContentWatcher.send(:handle_changes, [ bad ], [], [])
    assert ContentWatcher.watcher_errors.key?("posts/zz-watcher-bad.md")

    ContentWatcher.stubs(:process_file).returns(nil)
    ContentWatcher.send(:handle_changes, [ bad ], [], [])

    assert_empty ContentWatcher.watcher_errors
    assert_not File.exist?(ContentWatcher::ERRORS_FILE)
  end

  test "media addresses: present, deleted, and in a folder that's gone" do
    assert_equal "/media/images/a.png", ContentWatcher.media_web_path(site("media/images/a.png"))
    assert_equal "/media/zz-no-such-folder/a.png", ContentWatcher.media_web_path(site("media/zz-no-such-folder/a.png"))
  end
end
