# frozen_string_literal: true

require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  test "serves the public search index as JSON" do
    Post.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "indexed.md"),
      content: "Findable body.",
      metadata: { "title" => "Indexed Post", "status" => "published", "audience" => "everyone" }
    )

    get search_index_path

    assert_response :success
    assert_equal "application/json", response.media_type
    body = JSON.parse(response.body)
    titles = body["entries"].map { |e| e["title"] }
    assert_includes titles, "Indexed Post"
  end
end
