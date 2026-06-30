require "test_helper"

# HasMarkdownExtensions#render_gallery — grid vs. carousel, click-to-zoom
# overlays, and directive parsing. (The responsive <picture> conversion of
# the emitted <img data-sizes> is handled later by process_responsive_images
# and covered elsewhere; here we assert the gallery structure.)
class GalleryRenderingTest < ActiveSupport::TestCase
  class Dummy
    include HasMarkdownExtensions
  end

  def render_gallery(content, **opts)
    Dummy.new.send(:render_gallery, content, **opts)
  end

  test "renders a grid with rows split by blank lines, capped at 3 columns" do
    html = render_gallery(
      "![a](/media/images/a.jpg)\n\n" \
      "![b](/media/images/b.jpg)![c](/media/images/c.jpg)![d](/media/images/d.jpg)![e](/media/images/e.jpg)"
    )
    assert_includes html, "gallery-col-1", "first row has one image"
    assert_includes html, "gallery-col-3", "second row caps at 3 columns"
    refute_includes html, "gallery-carousel"
  end

  test "every image is a popover zoom trigger with a matching overlay" do
    html = render_gallery("![a](/media/images/a.jpg)\n![b](/media/images/b.jpg)", index: 0)

    assert_equal 2, html.scan('class="gallery-zoom-link"').size
    %w[gz-0-0 gz-0-1].each do |id|
      assert_includes html, %(popovertarget="#{id}"), "popover trigger for #{id}"
      assert_includes html, %(id="#{id}" class="gallery-zoom" popover), "popover overlay for #{id}"
    end
    assert_includes html, %(data-sizes="100vw"), "zoom overlay pulls the largest variant"
  end

  test "slideshow: true renders a carousel and consumes the directive" do
    html = render_gallery("![a](/media/images/a.jpg)\n![b](/media/images/b.jpg)\nslideshow: true")

    assert_includes html, "gallery-carousel"
    assert_includes html, "gallery-track"
    assert_includes html, "data-gallery-carousel"
    refute_includes html, "slideshow:", "directive must not leak into the output"
  end

  test "carousel preserves image order" do
    html = render_gallery(
      "![one](/media/images/1.jpg)\n![two](/media/images/2.jpg)\n![three](/media/images/3.jpg)\nslideshow: true"
    )
    order = html.scan(%r{/media/images/(\d)\.jpg}).flatten.first(3)
    assert_equal %w[1 2 3], order
  end

  test "captions render markdown; only whitelisted directives are config" do
    html = render_gallery("![a](/media/images/a.jpg) (*A **bold** caption*)")
    assert_includes html, "<figcaption>"
    assert_includes html, "<strong>bold</strong>"
  end

  test "anchors are namespaced by the per-page gallery index" do
    assert_includes render_gallery("![a](/media/images/a.jpg)", index: 0), "gz-0-0"
    assert_includes render_gallery("![a](/media/images/a.jpg)", index: 1), "gz-1-0"
  end

  test "an empty gallery renders nothing" do
    assert_equal "", render_gallery("\n\n")
  end
end
