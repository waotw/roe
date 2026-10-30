# frozen_string_literal: true

require "test_helper"

# site.yml is the one place site-level settings are read from, and the read is
# memoised because ApplicationMailer's `default from:` lambda runs once per
# message — a newsletter batch was re-parsing the file per recipient.
class SiteConfigReadTest < ActiveSupport::TestCase
  test "the file is parsed once and reused while it hasn't changed" do
    with_site_config("author_email" => "a@example.com")
    SiteConfig.get("author_email") # prime

    YAML.expects(:load_file).never

    5.times { assert_equal "a@example.com", SiteConfig.get("author_email") }
  end

  test "a changed file is picked up without anyone clearing a cache" do
    with_site_config("author_email" => "first@example.com")
    assert_equal "first@example.com", SiteConfig.get("author_email")

    # Written straight to disk — no sync_from_file, no reload!. This is the
    # rake-task and text-editor case, where nothing invalidates anything.
    File.write(SiteConfig::SITE_FILE, { "author_email" => "second@example.com" }.to_yaml)

    assert_equal "second@example.com", SiteConfig.get("author_email")
  end

  test "reading config does not need the database" do
    # Solid Cache is database-backed, so the cached-record path can't answer
    # when the database is gone. The file can, which is the point of reading it.
    with_site_config("author_email" => "a@example.com")
    SiteConfig.reset_file_cache!

    SiteConfig.expects(:find_by).never
    Rails.cache.expects(:fetch).never

    assert_equal "a@example.com", SiteConfig.get("author_email")
  end

  test "a change of the same byte length in the same second is still seen" do
    # bootsnap caches YAML.load_file on (mtime, size), and mtime here is
    # whole-second — so two writes of equal length inside one second hand back
    # the FIRST parse. The addresses below are deliberately the same length.
    # Reading the bytes ourselves instead of calling load_file is what makes
    # this pass; with load_file it returns aaa@ twice.
    with_site_config("author_email" => "aaa@example.com")
    assert_equal "aaa@example.com", SiteConfig.get("author_email")

    with_site_config("author_email" => "bbb@example.com")
    assert_equal "bbb@example.com", SiteConfig.get("author_email")
  end

  test "syncing a record from the file sees a same-length change too" do
    # Not just the read path. sync_from_file is what ContentWatcher calls when
    # a config file changes, so a stale parse here leaves the database record
    # disagreeing with the file on disk until the next save lands in a
    # different second. Reproduced before this was fixed.
    f = SiteConfig::SITE_FILE

    File.write(f, "static_generation_enabled: false\nauthor_email: aaa@example.com\n")
    SiteConfig.sync_from_file("site")
    assert_equal "aaa@example.com", SiteConfig.current("site").config["author_email"]

    File.write(f, "static_generation_enabled: false\nauthor_email: bbb@example.com\n")
    SiteConfig.sync_from_file("site")

    assert_equal "bbb@example.com", SiteConfig.current("site").config["author_email"],
                 "the record still holds the previous contents"
  end

  test "dotted keys still reach nested values" do
    with_site_config("theme" => { "active" => "bare" })

    assert_equal "bare", SiteConfig.get("theme.active")
  end

  test "a broken file is retried rather than remembered as nil" do
    File.write(SiteConfig::SITE_FILE, "author_email: \"unclosed\n  - [\n")
    SiteConfig.reset_file_cache!
    assert_nil SiteConfig.get("author_email")

    with_site_config("author_email" => "fixed@example.com")

    assert_equal "fixed@example.com", SiteConfig.get("author_email")
  end
end
