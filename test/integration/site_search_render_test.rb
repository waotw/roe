# frozen_string_literal: true

require "test_helper"

class SiteSearchRenderTest < ActionDispatch::IntegrationTest
  test "site search icon and overlay render on a public page" do
    Page.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "pages", "home.md"),
      content: "Welcome.",
      metadata: { "title" => "Home", "status" => "published", "audience" => "everyone" }
    )

    get "/"

    assert_response :success
    assert_select "div.site-search[data-controller=?]", "site-search"
    assert_select ".site-search-toggle[data-action*=?]", "site-search#open"
    assert_select "input.site-search-input"
    assert_select "[data-site-search-index-url-value=?]", "/search-index.json"
  end
end
