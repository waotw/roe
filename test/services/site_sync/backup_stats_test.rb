require "test_helper"

# Backups are rsync snapshots with hard links, so most files across snapshots
# share one inode. Adding up File.size counts every link separately: on one
# install 4,869 files across 17 backups summed to 3.07 GB while the disk held
# 253.6 MB. That's the number Finder reports, which is the reason for measuring
# it properly here.
class SiteSync::BackupStatsTest < ActiveSupport::TestCase
  setup do
    @root = SiteSync::BackupPaths.root
    @local = SiteSync::BackupPaths.local
    FileUtils.rm_rf(@root)
    FileUtils.mkdir_p(@local)
  end

  teardown { FileUtils.rm_rf(@root) }

  def make_backup(name, bytes: 4096)
    dir = File.join(@local, name)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "content.md"), "x" * bytes)
    dir
  end

  test "counts timestamped backups" do
    make_backup("2026-08-01-120000")
    make_backup("2026-08-02-120000")

    assert_equal 2, SiteSync::BackupStats.refresh!.count
  end

  # `latest` is a pointer to a backup already counted.
  test "latest and stray files aren't counted as backups" do
    make_backup("2026-08-01-120000")
    FileUtils.mkdir_p(File.join(@local, "latest"))
    File.write(File.join(@local, ".DS_Store"), "junk")

    assert_equal 1, SiteSync::BackupStats.refresh!.count
  end

  # The whole point: a hard-linked file is paid for once.
  test "hard links are counted once, not per link" do
    a = make_backup("2026-08-01-120000", bytes: 200_000)
    b = File.join(@local, "2026-08-02-120000")
    FileUtils.mkdir_p(b)
    FileUtils.ln(File.join(a, "content.md"), File.join(b, "content.md"))

    stats = SiteSync::BackupStats.refresh!
    apparent = 400_000

    assert_equal 2, stats.count
    assert_operator stats.bytes, :<, apparent,
      "a hard-linked file counted twice would overstate the size, as Finder does"
  end

  test "the numbers are recorded and read back" do
    make_backup("2026-08-01-120000")
    written = SiteSync::BackupStats.refresh!

    assert File.exist?(SiteSync::BackupStats.stats_path)

    read = SiteSync::BackupStats.current
    assert_equal written.count, read.count
    assert_equal written.bytes, read.bytes
  end

  # An install that predates this, or one that's never run a backup.
  test "with nothing recorded it computes once rather than reporting zero" do
    make_backup("2026-08-01-120000")
    FileUtils.rm_f(SiteSync::BackupStats.stats_path)

    assert_equal 1, SiteSync::BackupStats.current.count
  end

  test "no backups directory reports nothing rather than raising" do
    FileUtils.rm_rf(@root)

    stats = SiteSync::BackupStats.refresh!
    assert_equal 0, stats.count
    assert_equal 0, stats.bytes
  end

  # The stats file has to live inside the backups directory it describes.
  # Deriving its path separately meant this suite computed from its tmp fixture
  # and wrote the result into the real backups/.stats.json, so the dashboard
  # reported whatever the last test happened to create.
  test "the stats file is written inside the backups root it describes" do
    make_backup("2026-08-01-120000")
    SiteSync::BackupStats.refresh!

    assert_equal File.join(SiteSync::BackupPaths.root, ".stats.json"),
                 SiteSync::BackupStats.stats_path
    assert File.exist?(SiteSync::BackupStats.stats_path)
  end

  test "sizes read as something a person can parse" do
    s = SiteSync::BackupStats::Stats
    assert_equal "0 B", s.new(count: 0, bytes: 0).human_size
    assert_equal "512 B", s.new(count: 1, bytes: 512).human_size
    assert_equal "1.5 KB", s.new(count: 1, bytes: 1536).human_size
    assert_equal "254 MB", s.new(count: 1, bytes: 254 * 1024 * 1024).human_size
  end
end
