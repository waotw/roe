# frozen_string_literal: true

require "test_helper"

# `default_style` has been on the Cards settings form, and in the docs, since
# post-links existed — but nothing read it. render_post_link fell back to a
# hardcoded "small". It looked like it worked because the card builder wrote an
# explicit `style:` into every card it made, from a button template.
#
# With the templates gone and the builder leaving defaulted keys out of the
# block, a card genuinely arrives here with no style, so this setting is what
# decides. These render a real card rather than re-checking the arithmetic.
class PostLinkDefaultStyleTest < ActiveSupport::TestCase
  def stub_cards(section)
    SiteConfig.stubs(:default).returns(nil)
    SiteConfig.stubs(:default).with("cards", "post-link").returns(section)
  end

  def target
    Post.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "target.md"),
      content: "Body.",
      metadata: { "title" => "Target Post", "url_name" => "target-post", "status" => "published" }
    )
  end

  def rendered(extra = "")
    target
    Post.new(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "host.md"),
      content: "```card\ntype: post-link\npost: target-post\n#{extra}```",
      metadata: { "title" => "Host", "status" => "published" }
    ).to_html
  end

  # The wrapper carries the style as `post-link-<style>`.
  def style_class(html)
    html[/post-link-\w+/].to_s
  end

  test "a card with no style uses the site setting" do
    stub_cards({ "default_style" => "large" })

    assert_includes style_class(rendered), "large"
  end

  test "the card's own style still wins" do
    stub_cards({ "default_style" => "large" })

    assert_includes style_class(rendered("style: small\n")), "small"
  end

  test "with no setting it falls back to small" do
    stub_cards({})

    assert_includes style_class(rendered), "small"
  end

  # The config editor writes "" for a field nobody filled in, so an empty
  # string has to read as "not set" rather than becoming the style.
  test "a blank setting falls back to small rather than an empty class" do
    stub_cards({ "default_style" => "" })

    assert_includes style_class(rendered), "small"
  end
end
