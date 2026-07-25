require "test_helper"

# The sidebar's mobile behavior comes from its frontmatter: `mobile:` picks the
# relocation, `mobile_style:` optionally overrides the relocated menu's
# orientation. Both are parsed here; stub the frontmatter and assert the class
# tokens the layout will emit.
class LayoutHelperSidebarTest < ActionView::TestCase
  include LayoutHelper

  def frontmatter(hash)
    stubs(:parse_sidebar_frontmatter).returns(hash)
  end

  test "sidebar_mobile defaults to hidden and only accepts top/bottom/hidden" do
    frontmatter({})
    assert_equal "hidden", sidebar_mobile
  end

  test "sidebar_mobile reads a valid value" do
    frontmatter("mobile" => "top")
    assert_equal "top", sidebar_mobile
  end

  test "sidebar_mobile falls back to hidden on a bogus value" do
    frontmatter("mobile" => "sideways")
    assert_equal "hidden", sidebar_mobile
  end

  test "sidebar_mobile_style is nil when unset (sensible default applies)" do
    frontmatter({})
    assert_nil sidebar_mobile_style
  end

  test "sidebar_mobile_style reads horizontal and vertical" do
    frontmatter("mobile_style" => "vertical")
    assert_equal "vertical", sidebar_mobile_style
  end

  test "sidebar_mobile_style ignores a bogus value (falls back to the default)" do
    frontmatter("mobile_style" => "diagonal")
    assert_nil sidebar_mobile_style
  end
end
