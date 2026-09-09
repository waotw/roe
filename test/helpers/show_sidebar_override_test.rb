require "test_helper"

# show_sidebar?'s per-item override had two faults in one line:
#
#   return false if content.metadata["show_sidebar"] == false
#
# The metadata editor writes strings ("false"), and "false" == false is false
# in Ruby — so setting it in the admin did nothing. And @product wasn't in the
# list of things checked, though the scope logic below has always understood
# "products".
class ShowSidebarOverrideTest < ActionView::TestCase
  include LayoutHelper

  setup do
    @sidebar = File.join(RoeSitePaths::SITE_PATH, "layout", "sidebar.md")
    FileUtils.mkdir_p(File.dirname(@sidebar))
    @had_sidebar = File.exist?(@sidebar)
    File.write(@sidebar, "---\nscope: all\n---\n\nSidebar\n") unless @had_sidebar
  end

  teardown { FileUtils.rm_f(@sidebar) unless @had_sidebar }

  def item(klass, value)
    klass.new(metadata: { "title" => "T", "show_sidebar" => value })
  end

  test "the string the editor writes hides the sidebar" do
    @post = item(Post, "false")

    assert_not show_sidebar?, "the admin writes \"false\" as a string — that has to count"
  end

  test "a hand-written boolean still hides it" do
    @post = item(Post, false)

    assert_not show_sidebar?
  end

  test "a product's setting is honoured too" do
    @product = item(Product, "false")

    assert_not show_sidebar?, "@product was missing from the override entirely"
  end

  test "pages are unaffected by the change" do
    @page = item(Page, "false")

    assert_not show_sidebar?
  end

  test "unset falls through to the sidebar's own scope" do
    @post = Post.new(metadata: { "title" => "T" })

    assert show_sidebar?, "no setting means follow scope: all — not hidden"
  end

  # `true` used to do nothing — only `false` was handled — so a sidebar scoped
  # to pages couldn't be turned on for a single post, and the editor offered a
  # choice with no effect.
  test "true turns the sidebar on where the scope wouldn't" do
    File.write(@sidebar, "---\nscope: pages\n---\n\nSidebar\n")
    @post = item(Post, "true")

    assert show_sidebar?, "the file always wins"
  end

  test "without a setting the scope still decides" do
    File.write(@sidebar, "---\nscope: pages\n---\n\nSidebar\n")
    @post = Post.new(metadata: { "title" => "T" })

    assert_not show_sidebar?, "posts aren't in scope: pages"
  end

  test "no sidebar file means no sidebar, whatever the file says" do
    FileUtils.rm_f(@sidebar)
    @post = item(Post, "true")

    assert_not show_sidebar?
  end
end
