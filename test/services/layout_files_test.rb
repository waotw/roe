require "test_helper"

class LayoutFilesTest < ActiveSupport::TestCase
  DIR = File.join(RoeSitePaths::SITE_PATH, "layout")
  FILES = %w[header.md navigation.md].freeze

  setup do
    FileUtils.mkdir_p(DIR)
    @backup = {}
    FILES.each do |n|
      p = File.join(DIR, n)
      @backup[n] = File.exist?(p) ? File.read(p) : nil
      File.delete(p) if File.exist?(p)
    end
  end

  teardown do
    FILES.each do |n|
      p = File.join(DIR, n)
      File.delete(p) if File.exist?(p)
      File.write(p, @backup[n]) if @backup[n]
    end
  end

  def write(name, content)
    File.write(File.join(DIR, name), content)
  end

  test "path prefers header, falls back to navigation, else canonical header" do
    assert_equal File.join(DIR, "header.md"), LayoutFiles.path("header"), "canonical when neither exists"

    write("navigation.md", "nav")
    assert_equal File.join(DIR, "navigation.md"), LayoutFiles.path("header"), "legacy navigation still resolves"

    write("header.md", "hdr")
    assert_equal File.join(DIR, "header.md"), LayoutFiles.path("header"), "header wins"
  end

  test "exist? is true when either header or navigation is present" do
    assert_not LayoutFiles.exist?("header")
    write("navigation.md", "nav")
    assert LayoutFiles.exist?("header")
  end

  test "migration renames navigation.md to header.md, idempotently and without clobbering" do
    write("navigation.md", "the content")
    LayoutFiles.migrate_navigation_to_header!

    assert_not File.exist?(File.join(DIR, "navigation.md"))
    assert_equal "the content", File.read(File.join(DIR, "header.md"))

    # A stray navigation.md alongside an existing header.md is left untouched.
    write("navigation.md", "stray")
    LayoutFiles.migrate_navigation_to_header!
    assert File.exist?(File.join(DIR, "navigation.md")), "won't overwrite an existing header"
    assert_equal "the content", File.read(File.join(DIR, "header.md"))
  end
end
