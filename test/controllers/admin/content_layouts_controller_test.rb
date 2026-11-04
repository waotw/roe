require "test_helper"

# The Content section of the Layouts page: every type editable straight away,
# saved as the site's copy, back to Roe's default, and new layouts.
class Admin::ContentLayoutsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    FileUtils.mkdir_p(ContentLayout::SITE_DIR)
  end

  teardown do
    Dir.glob(File.join(ContentLayout::SITE_DIR, "*.yml")).each { |f| FileUtils.rm_f(f) }
  end

  test "the Layouts page lists the site files and every content type" do
    get "/admin/layouts"
    assert_response :success
    assert_select "h2", "Site"
    assert_select "h2", "Content"
    %w[article podcast page product documentation].each do |name|
      assert_select "a[href=?]", "/admin/layouts/content/#{name}/edit"
    end
    assert_includes response.body, "Roe's default"
  end

  test "a type on Roe's default opens Roe's copy, and saving makes it the site's" do
    get "/admin/layouts/content/article/edit"
    assert_response :success
    assert_includes response.body, File.read(ContentLayout.roe_default_path("article")).lines.last.strip
    assert_not File.exist?(ContentLayout.site_path("article")), "opening it writes nothing"

    patch "/admin/layouts/content/article", params: { content: "- body\r\n- title\r\n" }
    assert_redirected_to "/admin/layouts/content/article/edit"
    assert_equal "- body\n- title\n", File.read(ContentLayout.site_path("article"))
  end

  test "saving a layout with a problem saves it and says what's wrong" do
    patch "/admin/layouts/content/article", params: { content: "- title\n" }
    assert File.exist?(ContentLayout.site_path("article"))
    assert_match(/no body/, flash[:alert])
  end

  test "Use Roe's default deletes the site's copy" do
    File.write(ContentLayout.site_path("article"), "- body\n")
    delete "/admin/layouts/content/article"
    assert_not File.exist?(ContentLayout.site_path("article"))
    assert_redirected_to "/admin/layouts/content/article/edit"
  end

  test "New layout creates a file to use with layout:" do
    post "/admin/layouts/content", params: { name: "announcement" }
    assert_redirected_to "/admin/layouts/content/announcement/edit"
    assert File.exist?(ContentLayout.site_path("announcement"))

    get "/admin/layouts"
    assert_includes response.body, "layout: announcement"
  end

  test "New layout refuses a type's name and anything that isn't a plain name" do
    post "/admin/layouts/content", params: { name: "article" }
    assert_match(/already a layout/, flash[:alert])

    post "/admin/layouts/content", params: { name: "../evil" }
    assert_match(/lowercase/, flash[:alert])
    assert_empty Dir.glob(File.join(ContentLayout::SITE_DIR, "*.yml"))
  end

  test "a name that isn't a layout's can't be read or written" do
    get "/admin/layouts/content/nope/edit"
    assert_redirected_to "/admin/layouts"

    patch "/admin/layouts/content/..%2Fheader", params: { content: "x" }
    assert_response :not_found
  end
end
