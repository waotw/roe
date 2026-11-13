# frozen_string_literal: true

require "test_helper"

# The version store: every version a sync replaces or deletes is saved before
# it's touched, and any change can be put back.
class SiteSync::VersionsTest < ActiveSupport::TestCase
  DIR = "zz-versions-test"

  setup do
    FileUtils.rm_rf(SiteSync::Versions.root)
    FileUtils.mkdir_p(site(DIR))
  end

  teardown do
    FileUtils.rm_rf(SiteSync::Versions.root)
    FileUtils.rm_rf(site(DIR))
  end

  def site(rel) = File.join(RoeSitePaths::SITE_PATH, rel)

  def write(rel, text)
    File.write(site(rel), text)
    rel
  end

  def stored(sha) = File.read(SiteSync::Versions.object_path(sha))

  test "identical contents are stored once, under their SHA-256" do
    a = write("#{DIR}/a.md", "same words")
    b = write("#{DIR}/b.md", "same words")

    sha_a, size = SiteSync::Versions.save_file(site(a))
    sha_b, = SiteSync::Versions.save_file(site(b))

    assert_equal Digest::SHA256.hexdigest("same words"), sha_a
    assert_equal sha_a, sha_b
    assert_equal 10, size
    assert_equal 1, Dir.glob(File.join(SiteSync::Versions.objects_root, "??", "*")).size
  end

  test "a pull's old local version is saved before it's replaced, and its new one recorded" do
    rel = write("#{DIR}/post.md", "before the pull")
    recorder = SiteSync::Versions::Recorder.new
    recorder.save_local!([ rel ])
    File.write(site(rel), "what live had")
    recorder.finish!(kind: :sync, outcome: :completed)

    change = SiteSync::Versions.history_of(rel).first
    assert_equal [ "to_local", "changed" ], [ change[:direction], change[:action] ]
    assert_equal "before the pull", stored(change[:before_sha])
    assert_equal Digest::SHA256.hexdigest("what live had"), change[:after_sha]
    assert_equal "what live had", stored(change[:after_sha]), "a small version a sync leaves is kept too"
  end

  test "a large version a sync leaves isn't copied until something replaces it" do
    SiteSync::Versions.stubs(:after_copy_max).returns(5)
    rel = write("#{DIR}/episode.mp3", "old audio")
    recorder = SiteSync::Versions::Recorder.new
    recorder.save_local!([ rel ])
    File.write(site(rel), "new audio")
    recorder.finish!(kind: :sync, outcome: :completed)

    change = SiteSync::Versions.history_of(rel).first
    assert_equal "old audio", stored(change[:before_sha])
    assert_equal Digest::SHA256.hexdigest("new audio"), change[:after_sha]
    refute SiteSync::Versions.object?(change[:after_sha]), "it's on disk; stored once only when replaced"
  end

  test "a pull's deletion keeps the deleted file" do
    rel = write("#{DIR}/gone.md", "keep me")
    recorder = SiteSync::Versions::Recorder.new
    recorder.save_local!([ rel ], deleted: [ rel ])
    File.delete(site(rel))
    recorder.finish!(kind: :sync, outcome: :completed)

    change = SiteSync::Versions.history_of(rel).first
    assert_equal "deleted", change[:action]
    assert_equal "keep me", stored(change[:before_sha])
    assert_nil change[:after_sha]
  end

  test "a push keeps live's copies from the pre-push backup" do
    rel = write("#{DIR}/page.md", "local's new words")
    backup = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(backup, DIR))
    File.write(File.join(backup, rel), "live's old words")

    recorder = SiteSync::Versions::Recorder.new
    recorder.save_live!([ rel ], from: backup, peer: { rel => { "size" => 16 } })
    recorder.finish!(kind: :push, outcome: :completed)

    change = SiteSync::Versions.history_of(rel).first
    assert_equal [ "to_live", "changed" ], [ change[:direction], change[:action] ]
    assert_equal "live's old words", stored(change[:before_sha])
  ensure
    FileUtils.rm_rf(backup)
  end

  # One copy on disk: the store links live's copy in, and the pre-push backup
  # folder it came in is removed once it's saved.
  test "live's copy is linked into the store, not copied, and its backup folder goes" do
    rel = write("#{DIR}/page.md", "local's new words")
    root = File.join(SiteSync::Versions.root, "..", "live-content-#{SecureRandom.hex(4)}")
    SiteSync::BackupPaths.stubs(:live_content).returns(root)
    older, backup = File.join(root, "2026-01-01-000000"), File.join(root, "2026-01-02-000000")
    FileUtils.mkdir_p([ older, File.join(backup, DIR) ])
    File.write(File.join(backup, rel), "live's old words")
    File.symlink(File.basename(backup), File.join(root, "latest"))
    backed_up = File.stat(File.join(backup, rel))

    recorder = SiteSync::Versions::Recorder.new
    recorder.save_live!([ rel ], from: backup, peer: { rel => { "size" => 16 } })
    recorder.finish!(kind: :push, outcome: :completed)

    sha = SiteSync::Versions.history_of(rel).first[:before_sha]
    object = File.stat(SiteSync::Versions.object_path(sha))
    assert_equal [ backed_up.dev, backed_up.ino ], [ object.dev, object.ino ], "the same file on disk, not a copy"
    assert_equal "live's old words", stored(sha)
    assert_not File.exist?(backup)
    assert File.directory?(older), "only the folder this push made is removed"
    assert_equal File.basename(older), File.readlink(File.join(root, "latest"))
  ensure
    FileUtils.rm_rf(root)
  end

  test "a backup folder outside backups/live/content is left alone" do
    rel = write("#{DIR}/page.md", "new")
    backup = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(backup, DIR))
    File.write(File.join(backup, rel), "old")

    SiteSync::Versions::Recorder.new.save_live!([ rel ], from: backup, peer: { rel => { "size" => 3 } })
    assert File.exist?(File.join(backup, rel))
  ensure
    FileUtils.rm_rf(backup)
  end

  # Rule 2: no saved copy, no deletion. The sync stops instead.
  test "a live file the backup didn't bring down stops the push" do
    rel = "#{DIR}/missing.md"
    error = assert_raises(SiteSync::Versions::SaveFailed) do
      SiteSync::Versions::Recorder.new.save_live!([ rel ], from: Dir.mktmpdir, peer: { rel => { "size" => 3 } }, deleted: [ rel ])
    end
    assert_match rel, error.message
  end

  test "video web versions are left out on purpose and don't stop the push" do
    rel = "media/video/variants/clip-720p.mp4"
    recorder = SiteSync::Versions::Recorder.new
    recorder.save_live!([ rel ], from: Dir.mktmpdir, peer: { rel => { "size" => 9 } }, deleted: [ rel ])
    assert recorder.any?
  end

  test "a file new to live has no earlier version" do
    rel = write("#{DIR}/new.md", "new")
    recorder = SiteSync::Versions::Recorder.new
    recorder.save_live!([ rel ], from: nil, peer: {})
    recorder.finish!(kind: :push, outcome: :completed)

    change = SiteSync::Versions.history_of(rel).first
    assert_equal "added", change[:action]
    assert_nil change[:before_sha]
  end

  test "the site after any sync can be rebuilt: each path's version at that point" do
    rel = write("#{DIR}/doc.md", "one")
    first = record_change(rel, "two")    # one -> two
    second = record_change(rel, "three") # two -> three

    assert_equal Digest::SHA256.hexdigest("two"), SiteSync::Versions.state_after(first)[rel]
    assert_equal "two", stored(SiteSync::Versions.state_after(first)[rel]), "replaced since, so it was saved"
    assert_equal Digest::SHA256.hexdigest("three"), SiteSync::Versions.state_after(second)[rel]
  end

  test "trimming drops events past the cutoff and the copies only they used" do
    rel = write("#{DIR}/old.md", "v1")
    travel_to(40.days.ago) { record_change(rel, "v2") }  # saves v1
    record_change(rel, "v3")                              # saves v2

    SiteSync::Versions.trim!(days: 30)

    history = SiteSync::Versions.history_of(rel)
    assert_equal 1, history.size
    assert_equal "v2", stored(history.first[:before_sha]), "a version inside the window stays"
    refute SiteSync::Versions.object?(Digest::SHA256.hexdigest("v1")), "only the old event used it"
  end

  test "sync_history_days: 30 unless set; 0 or forever keeps everything" do
    { nil => 30, "" => 30, 7 => 7, "14" => 14, 0 => nil, "forever" => nil, "junk" => 30 }.each do |raw, days|
      SiteConfig.stubs(:get).with("sync_history_days").returns(raw)
      days ? assert_equal(days, SiteSync::Versions.keep_days, "for #{raw.inspect}") : assert_nil(SiteSync::Versions.keep_days, "for #{raw.inspect}")
    end
  end

  private

  # A pull replacing rel's contents with `text`, recorded as one sync.
  def record_change(rel, text)
    recorder = SiteSync::Versions::Recorder.new
    recorder.save_local!([ rel ])
    File.write(site(rel), text)
    recorder.finish!(kind: :sync, outcome: :completed)
  end
end
