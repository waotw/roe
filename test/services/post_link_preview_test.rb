# frozen_string_literal: true

require "test_helper"

class PostLinkPreviewTest < ActiveSupport::TestCase
  def make_post(url_name: "hello", **meta)
    Post.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "#{url_name}.md"),
      content: "The first paragraph of the body.",
      metadata: {
        "title" => "Hello World", "url_name" => url_name, "status" => "published",
        "subtitle" => "A subtitle", "excerpt" => "An excerpt.",
        "author" => "Ben", "date" => "2026-01-15"
      }.merge(meta)
    )
  end

  test "derives the inherited card fields for a post" do
    make_post
    f = PostLinkPreview.for("hello")

    assert_equal "Hello World", f[:title]
    assert_equal "A subtitle", f[:subtitle]
    assert_equal "An excerpt.", f[:excerpt]
    assert_equal "/posts/hello", f[:url]
    assert_equal "Ben", f[:author]
    assert_equal "Jan 15, 2026", f[:date]
  end

  test "falls back to the first paragraph when no excerpt is set" do
    make_post(url_name: "no-excerpt", "excerpt" => "")
    f = PostLinkPreview.for("no-excerpt")

    assert_equal "The first paragraph of the body.", f[:excerpt]
  end

  test "strips a known path prefix" do
    make_post
    assert_equal "/posts/hello", PostLinkPreview.for("/posts/hello")[:url]
  end

  test "returns nil for an unknown slug" do
    assert_nil PostLinkPreview.for("does-not-exist")
    assert_nil PostLinkPreview.for("")
  end
end
