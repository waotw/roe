# frozen_string_literal: true

require "test_helper"

class PostsHelperTest < ActionView::TestCase
  # HTML as produced by to_html for an ordered list with a paid-content
  # gate in the middle: the gate splits the list into two <ol>s.
  GATED_ORDERED = <<~HTML
    <ol>
      <li>First item</li>
      <li>Second item</li>
    </ol>

    <!-- PAID_CONTENT_GATE -->
    <div class="paid-content-gate">
      <p>Upgrade to continue</p>
      <a href="/upgrade" class="btn-primary">Become a member</a>
    </div>

    <ol>
      <li>Third item</li>
      <li>Fourth item</li>
    </ol>
  HTML

  test "paid members get one continuous ordered list, gate removed" do
    result = strip_paywall_gate(GATED_ORDERED)

    assert_equal 1, result.scan(/<ol/).size, "the two <ol>s should be merged into one"
    assert_equal 4, result.scan(/<li>/).size
    refute_includes result, "PAID_CONTENT_GATE"
    refute_includes result, "paid-content-gate"
    # Order preserved across the merge.
    assert result.index("First item") < result.index("Third item")
  end

  test "unordered lists are merged too, not cross-merged with ol" do
    html = GATED_ORDERED.gsub("<ol", "<ul").gsub("</ol>", "</ul>")
    result = strip_paywall_gate(html)

    assert_equal 1, result.scan(/<ul/).size
    assert_equal 4, result.scan(/<li>/).size
  end

  test "gate not inside a list is simply stripped" do
    html = <<~HTML
      <p>Free intro.</p>
      <!-- PAID_CONTENT_GATE -->
      <div class="paid-content-gate"><p>Upgrade</p></div>
      <p>Paid body.</p>
    HTML

    result = strip_paywall_gate(html)

    refute_includes result, "PAID_CONTENT_GATE"
    assert_includes result, "Free intro."
    assert_includes result, "Paid body."
  end

  test "content without a gate is unchanged" do
    html = "<ol>\n  <li>One</li>\n  <li>Two</li>\n</ol>\n"
    assert_equal html, strip_paywall_gate(html)
  end
end
