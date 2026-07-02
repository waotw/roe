require "test_helper"

class Admin::PagesDuplicateTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    @dir = File.join(RoeSitePaths::SITE_PATH, "pages")
    FileUtils.mkdir_p(@dir)
    File.write(File.join(@dir, "my-page.md"), "---\ntitle: My Page\nstatus: draft\n---\nBody\n")
    ContentSync.sync_file(File.join(@dir, "my-page.md"))
    @page = Page.where("json_extract(metadata, '$.title') = ?", "My Page").first
  end

  teardown do
    Dir.glob(File.join(@dir, "my-page*.md")).each { |f| File.delete(f) }
  end

  test "duplicate creates a numbered copy and redirects to its editor" do
    assert @page, "source page synced from file"

    assert_difference -> { Page.count }, 1 do
      post duplicate_admin_page_path(@page)
    end

    assert File.exist?(File.join(@dir, "my-page-2.md"))
    dup = Page.order(:id).last
    assert_equal "My Page 2", dup.title
    assert_redirected_to edit_admin_page_path(dup)
  end

  test "rename returns to the editor with return_to and renames on disk" do
    patch rename_admin_page_path(@page),
          params: { new_filename: "my-page-renamed", return_to: edit_admin_page_path(@page) }

    assert_redirected_to edit_admin_page_path(@page)
    assert File.exist?(File.join(@dir, "my-page-renamed.md"))
  end

  test "editor renders the filename rename control and duplicate button" do
    get edit_admin_page_path(@page)

    assert_response :success
    assert_select "form[action=?]", duplicate_admin_page_path(@page)
    assert_includes response.body, "my-page.md"
  end
end
