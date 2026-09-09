require "test_helper"

# Four copies of snipcart.js were loading on a browse through the store, each
# binding its own click handler, so one "Add to Cart" registered four times.
#
# Turbo Drive re-executes body <script>s on navigation, and Snipcart's loader
# can't tell it has already run — its check for an existing copy queries
# `src[src$="snipcart.js"]`, a <src> tag that doesn't exist, so it's always
# null and it appends another script every time.
class SnipcartSingleLoadTest < ActiveSupport::TestCase
  def html_for(snippet)
    config = SnipcartConfig.new
    config.stubs(:current_snippet).returns(snippet)
    config.current_snippet_html.to_s
  end

  test "the loader is marked so Turbo won't re-run it" do
    html = html_for(%(<script>window.SnipcartSettings={};</script>))

    assert_includes html, 'data-turbo-eval="false"'
  end

  test "every script in the snippet is marked, not just the first" do
    html = html_for(%(<script>a()</script>\n<script src="https://cdn.snipcart.com/x.js"></script>))

    assert_equal 2, html.scan('data-turbo-eval="false"').length
  end

  test "the script's own attributes survive" do
    html = html_for(%(<script src="https://cdn.snipcart.com/themes/v3.7.2/default/snipcart.js"></script>))

    assert_includes html, 'src="https://cdn.snipcart.com/themes/v3.7.2/default/snipcart.js"'
    assert_includes html, 'data-turbo-eval="false"'
  end

  # Re-saving the integration shouldn't stack the attribute.
  test "a snippet that already carries the flag isn't marked twice" do
    html = html_for(%(<script data-turbo-eval="false" src="x.js"></script>))

    assert_equal 1, html.scan("data-turbo-eval").length
  end

  test "non-script markup is untouched" do
    html = html_for(%(<!-- Snipcart Live Mode -->\n<div id="x"></div>))

    assert_not_includes html, "data-turbo-eval"
    assert_includes html, "<!-- Snipcart Live Mode -->"
  end

  test "an empty snippet renders nothing" do
    assert_nil html_for("").presence
    assert_nil html_for(nil).presence
  end

  test "the result is still marked html_safe" do
    config = SnipcartConfig.new
    config.stubs(:current_snippet).returns("<script>x()</script>")

    assert_predicate config.current_snippet_html, :html_safe?
  end
end
