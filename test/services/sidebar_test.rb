require "test_helper"

# The sidebar's rules moved out of LayoutHelper so the metadata editor can ask
# the same questions the layout does — whether to offer a show_sidebar field at
# all, and what it should default to.
class SidebarTest < ActiveSupport::TestCase
  setup do
    @path = Sidebar.path
    FileUtils.mkdir_p(File.dirname(@path))
    @original = File.exist?(@path) ? File.binread(@path) : nil
  end

  teardown do
    @original ? File.write(@path, @original) : FileUtils.rm_f(@path)
  end

  def write_sidebar(scope)
    File.write(@path, scope.nil? ? "---\n---\n\nSidebar\n" : "---\nscope: #{scope}\n---\n\nSidebar\n")
  end

  test "no file means no sidebar anywhere" do
    FileUtils.rm_f(@path)

    assert_not Sidebar.exists?
    assert_not Sidebar.covers?("post")
    assert_not Sidebar.covers?("page")
  end

  test "no scope means the whole site" do
    write_sidebar(nil)

    assert_equal [ "all" ], Sidebar.scope
    assert Sidebar.covers?("post")
    assert Sidebar.covers?("page")
    assert Sidebar.covers?("product")
  end

  test "a scope narrows it to the types it names" do
    write_sidebar("pages")

    assert Sidebar.covers?("page")
    assert_not Sidebar.covers?("post")
    assert_not Sidebar.covers?("product")
  end

  test "a comma-separated scope covers each type" do
    write_sidebar("pages, posts")

    assert Sidebar.covers?("page")
    assert Sidebar.covers?("post")
    assert_not Sidebar.covers?("product")
  end

  # The editor asks in the singular, scopes are written in the plural.
  test "singular and plural both answer" do
    write_sidebar("posts")

    assert Sidebar.covers?("post")
    assert Sidebar.covers?("posts")
  end

  test "an unparseable file doesn't raise" do
    File.write(@path, "---\nscope: [unclosed\n---\n")

    assert_nothing_raised { Sidebar.scope }
  end
end
