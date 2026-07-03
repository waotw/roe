# frozen_string_literal: true

require "test_helper"
require "ostruct"

class SearchHelperTest < ActionView::TestCase
  # --- parse_search_scope --------------------------------------------------

  test "parses a source token" do
    assert_equal({ sources: [ "documentation" ] }, parse_search_scope("documentation"))
  end

  test "parses a post-type token as a postType" do
    assert_equal({ postTypes: [ "podcast" ] }, parse_search_scope("podcast"))
  end

  test "splits sources and post types across delimiters" do
    assert_equal(
      { sources: [ "posts" ], postTypes: [ "podcast" ] },
      parse_search_scope("posts / podcast")
    )
  end

  test "blank scope is nil" do
    assert_nil parse_search_scope("")
  end

  # --- site_search_scope (auto by content type) ----------------------------

  test "documentation page auto-scopes to documentation" do
    @doc = Object.new
    assert_equal({ sources: [ "documentation" ] }, site_search_scope)
  end

  test "product page auto-scopes to products" do
    @product = Object.new
    assert_equal({ sources: [ "products" ] }, site_search_scope)
  end

  test "post auto-scopes to its own post_type" do
    @post = OpenStruct.new(post_type: "podcast")
    assert_equal({ postTypes: [ "podcast" ] }, site_search_scope)
  end

  test "post with no post_type falls back to posts" do
    @post = OpenStruct.new(post_type: "")
    assert_equal({ sources: [ "posts" ] }, site_search_scope)
  end

  test "collection archive page scopes to its source (nested source uses base)" do
    @source = "documentation/guides"
    @tags = []
    assert_equal({ sources: [ "documentation" ] }, site_search_scope)
  end

  test "collection with post_type and tags scopes to all three" do
    @source = "posts"
    @post_type = "podcast"
    @tags = [ "news" ]
    assert_equal(
      { sources: [ "posts" ], postTypes: [ "podcast" ], tagsInclude: [ "news" ] },
      site_search_scope
    )
  end

  test "does not crash when @page is a pagination integer" do
    @page = 1
    @source = "posts"
    assert_equal({ sources: [ "posts" ] }, site_search_scope)
  end

  test "page frontmatter search_scope wins over auto" do
    @page = OpenStruct.new(metadata: { "search_scope" => "documentation, podcast" })
    assert_equal(
      { sources: [ "documentation" ], postTypes: [ "podcast" ] },
      site_search_scope
    )
  end

  test "plain page (no frontmatter) is site-wide" do
    @page = OpenStruct.new(metadata: {})
    assert_nil site_search_scope
  end
end
