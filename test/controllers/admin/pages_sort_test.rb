require "test_helper"

class Admin::PagesSortTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    @nav = File.join(RoeSitePaths::SITE_PATH, "layout", "navigation.md")
    FileUtils.mkdir_p(File.dirname(@nav))
    File.delete(@nav) if File.exist?(@nav)
  end

  teardown do
    File.delete(@nav) if File.exist?(@nav)
  end

  def page_named(title, url_name)
    create(:page, metadata: { "title" => title, "url_name" => url_name, "status" => "published" })
  end

  def order_of(*pages)
    body = response.body
    pages.map { |p| body.index(p.title) }
  end

  test "orders by navigation.md, then alphabetically for pages not in the nav" do
    about   = page_named("About", "about")     # nav #1
    contact = page_named("Contact", "contact") # nav #2
    zebra   = page_named("Zebra", "zebra")     # not in nav
    apple   = page_named("Apple", "apple")     # not in nav
    File.write(@nav, "[About](/about) [Contact](/contact)\n")

    get admin_pages_path
    assert_response :success

    positions = order_of(about, contact, apple, zebra)
    assert positions.none?(&:nil?), "all four pages rendered"
    assert_equal positions.sort, positions,
      "expected About < Contact (nav order) < Apple < Zebra (alpha)"
  end

  test "orders alphabetically when navigation.md is absent" do
    zebra = page_named("Zebra", "zebra")
    apple = page_named("Apple", "apple")

    get admin_pages_path
    assert_response :success

    positions = order_of(apple, zebra)
    assert positions.none?(&:nil?)
    assert positions.first < positions.last, "Apple before Zebra"
  end
end
