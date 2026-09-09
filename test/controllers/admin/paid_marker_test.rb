# frozen_string_literal: true

require "test_helper"

# The $ from the media browser, carried into the content indexes so paid
# content is visible at a glance rather than only after opening a post.
class Admin::PaidMarkerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }

  def make_post(title, audience)
    Post.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "#{title.parameterize}.md"),
      content: "Body.",
      metadata: { "title" => title, "url_name" => title.parameterize,
                  "status" => "published", "date" => "2026-01-01", "audience" => audience }
    )
  end

  def make_page(title, audience)
    Page.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "pages", "#{title.parameterize}.md"),
      content: "Body.",
      metadata: { "title" => title, "url_name" => title.parameterize,
                  "status" => "published", "audience" => audience }
    )
  end

  test "a paid post is marked and a free one isn't" do
    make_post("Paid Post", "paid")
    make_post("Free Post", "everyone")

    get admin_posts_path

    assert_response :success
    assert_select "[title=?]", "Paid — members only", count: 1
  end

  test "a paid page is marked" do
    make_page("Paid Page", "paid")
    make_page("Free Page", "everyone")

    get admin_pages_path

    assert_response :success
    assert_select "[title=?]", "Paid — members only", count: 1
  end

  # The toggle filters client-side, so the row has to carry the fact.
  test "post rows carry whether they're paid" do
    make_post("Paid Post", "paid")
    make_post("Free Post", "everyone")

    get admin_posts_path

    assert_select "tr[data-paid=?]", "true", count: 1
    assert_select "tr[data-paid=?]", "false", count: 1
  end

  test "the paid toggle renders beside the count" do
    get admin_posts_path

    assert_select "[data-posts-filter-target=?]", "paidToggle", count: 1
    assert_select "[data-posts-filter-target=?]", "count", count: 1
  end

  # A post with no audience at all reads as free, not as missing.
  test "a post with no audience is unmarked" do
    Post.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "bare.md"),
      content: "Body.",
      metadata: { "title" => "Bare", "url_name" => "bare", "status" => "published" }
    )

    get admin_posts_path

    assert_select "[title=?]", "Paid — members only", count: 0
    assert_select "tr[data-paid=?]", "false"
  end
end
