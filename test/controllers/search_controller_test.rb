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

  # --- members' index -------------------------------------------------------

  def paid_post!
    Post.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "walled.md"),
      content: "Free intro.\n\n```form for: paid_content\nUpgrade\n```\n\nSecret paid body.",
      metadata: { "title" => "Walled", "status" => "published", "audience" => "paid" }
    )
  end

  test "members index is forbidden to guests" do
    paid_post!
    get members_search_index_path
    assert_response :forbidden
  end

  test "members index is forbidden to free members" do
    paid_post!
    sign_in_member(create(:member, tier: :free, status: :active))
    get members_search_index_path
    assert_response :forbidden
  end

  test "members index gives a paid member the full text of paid posts" do
    paid_post!
    sign_in_member(create(:member, tier: :paid, status: :active))
    get members_search_index_path

    assert_response :success
    entry = JSON.parse(response.body)["entries"].find { |e| e["title"] == "Walled" }
    assert entry
    assert_includes entry["text"], "Secret paid body"
  end

  test "public index never carries text below the paywall, whoever asks" do
    paid_post!
    sign_in_member(create(:member, tier: :paid, status: :active))
    get search_index_path

    entry = JSON.parse(response.body)["entries"].find { |e| e["title"] == "Walled" }
    refute_includes entry.to_s, "Secret paid body"
  end
end
