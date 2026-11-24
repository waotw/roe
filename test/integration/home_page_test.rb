require "test_helper"

# The home page is the page at `/`, found by page_type: home, then the file
# pages/home.md, then url_name home. Renaming it (file or url_name) keeps it
# at `/`, in links and in menus.
class HomePageTest < ActionDispatch::IntegrationTest
  setup { @created = [] }
  teardown { @created.each { |path| FileUtils.rm_f(path) } }

  def page(rel, front, body = "Text.\n")
    path = File.join(RoeSitePaths::SITE_PATH, "pages", rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "---\ntitle: #{File.basename(rel, '.md').titleize}\nstatus: published\n#{front}---\n#{body}")
    @created << path
    ContentSync.sync_file(path)
    Page.find_by!(file_path: RoeSitePaths.normalize(path))
  end

  test "page_type home is the page at / whatever its file and url_name" do
    front = page("front-door.md", "url_name: front-door\npage_type: home\n", "Front door text.\n")
    other = page("hp-other.md", "url_name: hp-other\n")

    assert_equal front, Page.home
    assert front.home?
    refute other.home?
    assert_equal "/", front.public_url
    assert_equal "/hp-other", other.public_url

    get "/"
    assert_response :success
    assert_includes response.body, "Front door text."
  end

  test "an old site's page with url_name home is still the home page" do
    old = page("hp-old-home.md", "url_name: home\n", "Old home text.\n")

    assert_equal old, Page.home
    assert_equal "/", old.public_url
    get "/"
    assert_includes response.body, "Old home text."
  end

  test "links, cards and menus to the home page point at /" do
    page("front-door.md", "url_name: front-door\npage_type: home\n")
    linker = page("hp-linker.md", "url_name: hp-linker\n", <<~MD)
      [[front-door]]

      ```collection
      template: menu
      order: home, hp-linker
      ```
    MD

    html = linker.to_html.to_s
    assert_includes html, %(<a href="/">)
    assert_select Nokogiri::HTML.fragment(html), "ul.collection-menu a[href='/']", 1
  end

  test "the name home still finds the home page after a rename" do
    front = page("front-door.md", "url_name: front-door\npage_type: home\n")

    assert_equal [ front ], ItemName.matches("home")
    assert_equal front, ItemName.pick("home", Page.all.to_a)
    assert_empty ItemName.matches("home.md")
  end

  test "the starter home.md isn't put back beside a renamed home page" do
    page("front-door.md", "url_name: front-door\npage_type: home\n")
    assert_includes ConfigGenerator.new.skip_paths_for_minimum, "pages/home.md"
  end

  test "renaming the home page writes no redirect from /" do
    front = page("front-door.md", "url_name: front-door\npage_type: home\n")
    controller = Admin::PagesController.new
    controller.params = ActionController::Parameters.new(create_redirect_from: "1")

    RedirectManager.expects(:add_301).never
    controller.send(:add_rename_redirect, Page, front.public_url, { "url_name" => "new-door", "status" => "published" }, front.file_path)
  end
end
