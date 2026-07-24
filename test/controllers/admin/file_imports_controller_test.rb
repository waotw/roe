require "test_helper"
require "zip"
require "tmpdir"

class Admin::FileImportsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }

  def build_zip(path)
    Zip::File.open(path, create: true) do |z|
      z.get_output_stream("_posts/2024-01-05-hello.md") { |f| f.write "---\ntitle: Hello\n---\n# Hi\n\ntext\n" }
      z.get_output_stream("about.html") { |f| f.write "<html><head><title>About</title></head><body><main><p>Us</p></main></body></html>" }
      z.get_output_stream("notes/thing.md") { |f| f.write "no signals here" }
    end
  end

  test "index renders the upload form" do
    get admin_file_imports_path
    assert_response :success
    assert_select "input[type=file]"
  end

  test "upload shows the review with a choice for ambiguous files, then import creates drafts" do
    before_posts = Dir[File.join(RoeSitePaths::SITE_POSTS_PATH, "*.md")]
    before_pages = Dir[File.join(RoeSitePaths::SITE_PAGES_PATH, "*.md")]

    Dir.mktmpdir do |dir|
      zip = File.join(dir, "site.zip")
      build_zip(zip)

      post admin_file_imports_path,
           params: { file_import: { archive: Rack::Test::UploadedFile.new(zip, "application/zip") } }
      assert_response :success
      assert_select "input[name=token]"
      assert_select "input[name='kinds[notes/thing.md]']", true, "ambiguous file gets a choice"
      token = css_select("input[name=token]").first["value"]

      post run_admin_file_imports_path, params: { token: token, kinds: { "notes/thing.md" => "page" } }
      assert_redirected_to admin_posts_path(status: "draft", sort: "updated-desc")
      assert_match(/Imported/, flash[:notice])

      assert File.exist?(File.join(RoeSitePaths::SITE_POSTS_PATH, "2024-01-05-hello.md")), "post filename preserved"
      assert File.exist?(File.join(RoeSitePaths::SITE_PAGES_PATH, "about.md")), "html imported as page"
      assert File.exist?(File.join(RoeSitePaths::SITE_PAGES_PATH, "thing.md")), "ambiguous forced to page"
    end
  ensure
    (Dir[File.join(RoeSitePaths::SITE_POSTS_PATH, "*.md")] - before_posts).each { |f| File.delete(f) }
    (Dir[File.join(RoeSitePaths::SITE_PAGES_PATH, "*.md")] - before_pages).each { |f| File.delete(f) }
  end

  test "a bad token is handled gracefully" do
    post run_admin_file_imports_path, params: { token: "nope" }
    assert_redirected_to admin_file_imports_path
    assert_match(/expired/, flash[:alert])
  end

  test "run records an import, index lists it, and delete removes its draft content" do
    before_posts = Dir[File.join(RoeSitePaths::SITE_POSTS_PATH, "*.md")]
    before_pages = Dir[File.join(RoeSitePaths::SITE_PAGES_PATH, "*.md")]

    Dir.mktmpdir do |dir|
      zip = File.join(dir, "site.zip")
      build_zip(zip)

      post admin_file_imports_path,
           params: { file_import: { archive: Rack::Test::UploadedFile.new(zip, "application/zip") } }
      token = css_select("input[name=token]").first["value"]

      assert_difference -> { Import.where(source_type: "files").count }, 1 do
        post run_admin_file_imports_path, params: { token: token, kinds: { "notes/thing.md" => "post" } }
      end

      import = Import.where(source_type: "files").order(:id).last
      assert_equal 2, import.stats["posts"].to_i, "hello + thing"
      assert_equal 1, import.stats["pages"].to_i, "about.html"
      assert_operator import.ref_draft_count, :>=, 3, "content tagged with import_ref"

      get admin_file_imports_path
      assert_response :success
      assert_select "a", text: "Import ##{import.id}"

      hello = File.join(RoeSitePaths::SITE_POSTS_PATH, "2024-01-05-hello.md")
      assert File.exist?(hello)

      assert_difference -> { Import.count }, -1 do
        delete admin_file_import_path(import)
      end
      assert_not File.exist?(hello), "draft file removed with the import"
      assert_equal 0, Post.where("json_extract(metadata, '$.import_ref') = ?", import.id).count
    end
  ensure
    (Dir[File.join(RoeSitePaths::SITE_POSTS_PATH, "*.md")] - before_posts).each { |f| File.delete(f) }
    (Dir[File.join(RoeSitePaths::SITE_PAGES_PATH, "*.md")] - before_pages).each { |f| File.delete(f) }
  end
end
