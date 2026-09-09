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
end
