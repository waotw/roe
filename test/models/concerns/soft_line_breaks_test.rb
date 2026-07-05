# frozen_string_literal: true

require "test_helper"

class SoftLineBreaksTest < ActiveSupport::TestCase
  def render_body(body)
    Post.new(content: body, metadata: { "title" => "T", "status" => "published" }).to_html
  end

  test "off by default: a single newline does not become a <br>" do
    SiteConfig.stubs(:get)
    SiteConfig.stubs(:get).with("soft_line_breaks").returns(nil)

    assert_not_includes render_body("line one\nline two"), "<br"
  end

  test "on: a single newline becomes a <br>" do
    SiteConfig.stubs(:get)
    SiteConfig.stubs(:get).with("soft_line_breaks").returns("true")

    assert_includes render_body("line one\nline two"), "<br"
  end
end
