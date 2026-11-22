require "test_helper"

# Roe finds the pages it shows at its own steps by page_type, then by the
# file it installed, then by the url_name they used to need.
class SystemPagesTest < ActiveSupport::TestCase
  setup { @created = [] }
  teardown { @created.each { |path| FileUtils.rm_f(path) } }

  def page(rel, front)
    path = File.join(RoeSitePaths::SITE_PATH, "pages", rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "---\ntitle: A page\nstatus: published\n#{front}---\nText.\n")
    @created << path
    ContentSync.sync_file(path)
    Page.find_by!(file_path: RoeSitePaths.normalize(path))
  end

  test "page_type wins, whatever the page is called" do
    declared = page("thanks-for-buying.md", "url_name: thanks\npage_type: checkout-success\n")
    page("members/checkout-success.md", "url_name: checkout-success\n")

    assert_equal declared, SystemPages.find("checkout-success")
    assert_equal "/thanks", SystemPages.path("checkout-success")
  end

  test "the installed file is found under any url_name" do
    installed = page("members/donation-cancel.md", "url_name: no-donation-today\n")
    assert_equal installed, SystemPages.find("donation-cancel")
  end

  test "an old site's url_name still works" do
    old = page("somewhere-else.md", "url_name: check-email\n")
    assert_equal old, SystemPages.find("check-email")
  end

  test "nothing found gives the fallback" do
    assert_nil SystemPages.find("archive")
    assert_equal "/posts", SystemPages.path("archive", fallback: "/posts")
  end
end
