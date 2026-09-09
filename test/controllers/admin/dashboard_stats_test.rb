require "test_helper"

class DashboardStatsTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }

  teardown do
    Post.where("file_path LIKE ?", "%zz-dash-%").destroy_all
    Product.where("file_path LIKE ?", "%zz-dash-%").destroy_all
  end

  def make_post(type)
    post = Post.new(metadata: {
      "title" => "ZZ Dash #{type}", "url_name" => "zz-dash-#{type}",
      "status" => "published", "post_type" => type, "date" => "2026-01-01"
    })
    post.file_path = "posts/zz-dash-#{type}.md"
    post.save!
    post
  end

  def make_product
    product = Product.new(metadata: {
      "title" => "ZZ Dash Product", "url_name" => "zz-dash-product",
      "status" => "published", "sku" => "ZZ-DASH-1", "price" => 10.0
    })
    product.file_path = "products/zz-dash-product.md"
    product.save!
    product
  end

  test "the dashboard renders" do
    get admin_root_path
    assert_response :success
  end

  test "posts and pages each get their own block" do
    get admin_root_path

    assert_select "div", text: /── Posts ──/
    assert_select "div", text: /── Pages ──/
    assert_select "div", text: /── System ──/
  end

  # The old table showed Total/Published/Drafts for posts and lost anything
  # unlisted entirely.
  test "unlisted content is shown" do
    get admin_root_path
    assert_match "Unlisted", response.body
  end

  test "system shows backups and database size" do
    get admin_root_path

    assert_match "Backups", response.body
    assert_match "Backups size", response.body
    assert_match "Database size", response.body
  end

  # Episodes, Tracks and Products earn a block only when there's something in
  # them — a plain blog stays a two-block grid.
  test "a type with no entries gets no block" do
    Post.stubs(:by_type).returns(Post.none)
    Product.stubs(:any?).returns(false)

    get admin_root_path

    assert_no_match "── Episodes ──", response.body
    assert_no_match "── Tracks ──", response.body
    assert_no_match "── Products ──", response.body
    assert_match "── Posts ──", response.body
  end

  test "podcasts get an Episodes block" do
    make_post("podcast")

    get admin_root_path

    assert_match "── Episodes ──", response.body
  end

  test "music gets a Tracks block" do
    make_post("music")

    get admin_root_path

    assert_match "── Tracks ──", response.body
  end

  test "products get their own block" do
    make_product

    get admin_root_path

    assert_match "── Products ──", response.body
  end

  # Posts becomes Articles when a type is split out, so an episode isn't
  # counted in both blocks.
  test "Posts narrows to Articles once a type has its own block" do
    make_post("podcast")

    get admin_root_path

    assert_match "── Articles ──", response.body
    assert_no_match "── Posts ──", response.body
  end

  test "the repair prompt only appears when something needs it" do
    PageStatusRepair.stubs(:count).returns(0)
    get admin_root_path
    assert_no_match "MISSING A STATUS", response.body

    PageStatusRepair.stubs(:count).returns(3)
    get admin_root_path
    assert_match "MISSING A STATUS", response.body
  end

  test "repairing reports what it did" do
    PageStatusRepair.stubs(:repair!).returns([ 1, 2 ])

    post admin_repair_page_statuses_path

    assert_redirected_to admin_root_path
    assert_match "Repaired 2 pages", flash[:notice]
  end

  test "repairing with nothing pending says so" do
    PageStatusRepair.stubs(:repair!).returns([])

    post admin_repair_page_statuses_path

    assert_match "Nothing to repair", flash[:notice]
  end
end
