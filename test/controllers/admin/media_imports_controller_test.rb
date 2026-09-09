require "test_helper"

class Admin::MediaImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    @created = []
  end
  teardown { @created.each { |f| File.delete(f) if File.exist?(f) } }

  def make_post(name, meta)
    slug = ContentWriter.new.write(kind: :post, filename: name, metadata: meta.merge("title" => name), body: "b")
    @created << File.join(RoeSitePaths::SITE_POSTS_PATH, "#{slug}.md")
  end

  test "index lists external media types with counts" do
    make_post("mi-a", { "image" => "https://cdn.example.com/x.jpg", "status" => "draft" })
    get admin_media_imports_path
    assert_response :success
    assert_select "input[name=?][value=?]", "types[]", "images"
  end

  test "create enqueues the job and redirects" do
    assert_enqueued_with(job: MediaImportJob) do
      post admin_media_imports_path, params: { types: [ "images" ] }
    end
    assert_redirected_to admin_media_imports_path
  end

  test "create with no types is rejected" do
    post admin_media_imports_path, params: { types: [] }
    assert_redirected_to admin_media_imports_path
    assert_match(/Pick at least one/, flash[:alert])
  end

  test "status returns json" do
    get status_admin_media_imports_path
    assert_response :success
    assert_equal "idle", JSON.parse(response.body)["state"]
  end
end
