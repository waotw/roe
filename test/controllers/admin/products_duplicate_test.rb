require "test_helper"

class Admin::ProductsDuplicateTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    @dir = File.join(RoeSitePaths::SITE_PATH, "products")
    FileUtils.mkdir_p(@dir)
    File.write(File.join(@dir, "my-product.md"), "---\ntitle: My Product\nstatus: draft\nprice: 5\nsku: X-1\n---\nBody\n")
    ContentSync.sync_file(File.join(@dir, "my-product.md"))
    @product = Product.where("json_extract(metadata, '$.title') = ?", "My Product").first
  end

  teardown do
    Dir.glob(File.join(@dir, "my-product*.md")).each { |f| File.delete(f) }
  end

  test "duplicate creates a numbered copy and redirects to its editor" do
    assert @product, "source product synced from file"

    assert_difference -> { Product.count }, 1 do
      post duplicate_admin_product_path(@product)
    end

    assert File.exist?(File.join(@dir, "my-product-2.md"))
    dup = Product.order(:id).last
    assert_equal "My Product 2", dup.title
    assert_redirected_to edit_admin_product_path(dup)
  end

  test "rename returns to the editor with return_to and renames on disk" do
    patch rename_admin_product_path(@product),
          params: { new_filename: "my-product-renamed", return_to: edit_admin_product_path(@product) }

    assert_redirected_to edit_admin_product_path(@product)
    assert File.exist?(File.join(@dir, "my-product-renamed.md"))
    refute File.exist?(File.join(@dir, "my-product.md"))
  end

  test "editor renders the filename rename control and duplicate button" do
    get edit_admin_product_path(@product)

    assert_response :success
    assert_select "form[action=?]", duplicate_admin_product_path(@product)
    assert_includes response.body, "my-product.md"
  end
end
