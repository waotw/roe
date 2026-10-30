require "test_helper"

# Site Sync tracks changes on size + mtime, so rewriting identical bytes reads
# as a real edit — "Refresh Sync Status" reporting files changed that weren't.
class SiteFileTest < ActiveSupport::TestCase
  setup do
    @dir  = Rails.root.join("tmp", "site_file_test")
    FileUtils.mkdir_p(@dir)
    @path = File.join(@dir, "config.yml")
  end

  teardown { FileUtils.rm_rf(@dir) }

  test "a new file is written" do
    assert SiteFile.write(@path, "a: 1\n")
    assert_equal "a: 1\n", File.read(@path)
  end

  test "changed content is written" do
    SiteFile.write(@path, "a: 1\n")
    assert SiteFile.write(@path, "a: 2\n")
    assert_equal "a: 2\n", File.read(@path)
  end

  # The whole point: a no-op save must not touch the file.
  test "identical content leaves the mtime alone" do
    SiteFile.write(@path, "a: 1\n")
    File.utime(Time.at(1_000_000), Time.at(1_000_000), @path)
    before = File.stat(@path).mtime.to_i

    assert_not SiteFile.write(@path, "a: 1\n"), "should report no write"

    assert_equal before, File.stat(@path).mtime.to_i,
      "an unchanged save must not bump mtime — Site Sync reads that as an edit"
  end

  test "missing parent directories are created" do
    nested = File.join(@dir, "a", "b", "c.yml")
    assert SiteFile.write(nested, "x: 1\n")
    assert_equal "x: 1\n", File.read(nested)
  end

  test "changed? answers without writing" do
    SiteFile.write(@path, "a: 1\n")
    assert_not SiteFile.changed?(@path, "a: 1\n")
    assert SiteFile.changed?(@path, "a: 2\n")
    assert SiteFile.changed?(File.join(@dir, "absent.yml"), "a: 1\n")
  end

  test "content is compared as bytes, not as a string with encoding" do
    SiteFile.write(@path, "héllo\n")
    assert_not SiteFile.write(@path, "héllo\n")
  end

  # ── read_yaml ────────────────────────────────────────────────────────────
  #
  # The read counterpart to .write, and every config read in the admin goes
  # through it. Not YAML.load_file, because bootsnap caches that on
  # (mtime, size) and mtime is whole-second on at least some filesystems.

  test "read_yaml sees a same-length change made in the same second" do
    path = Rails.root.join("tmp", "read_yaml_test.yml")
    File.write(path, "key: aaa@example.com\n")
    assert_equal "aaa@example.com", SiteFile.read_yaml(path)["key"]

    File.write(path, "key: bbb@example.com\n")

    assert_equal "bbb@example.com", SiteFile.read_yaml(path)["key"],
                 "a stale parse here is merged and written back by the config " \
                 "savers, discarding the save before it"
  ensure
    FileUtils.rm_f(path)
  end

  test "read_yaml returns nil for a missing file rather than raising" do
    # Callers pair it with `|| {}`, replacing an explicit File.exist? check.
    assert_nil SiteFile.read_yaml(Rails.root.join("tmp", "definitely_absent.yml"))
  end

  test "read_yaml passes permitted_classes through" do
    path = Rails.root.join("tmp", "read_yaml_date.yml")
    File.write(path, "when: 2026-09-13\n")

    assert_equal Date.new(2026, 9, 13),
                 SiteFile.read_yaml(path, permitted_classes: [ Date ])["when"]
  ensure
    FileUtils.rm_f(path)
  end
end
