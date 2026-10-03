# frozen_string_literal: true

require "test_helper"

# Verifies the web→email image rewrite: standalone <picture>/srcset collapses
# to a single absolute <img> at a retina variant, and galleries are dropped
# entirely (email can't render the CSS-grid/object-fit layout faithfully, so
# they're deferred to the variant epic rather than shown with ragged aspect
# ratios).
class NewsletterImageTransformerTest < ActiveSupport::TestCase
  SITE = "https://example.com"
  BASE = "/media/images/variants/photo"

  setup do
    @variants_dir = File.join(RoeSitePaths::SITE_PATH, "media", "images", "variants")
    FileUtils.mkdir_p(@variants_dir)
    # Empty files are enough for pick_variant's File.exist? check; FastImage
    # can't size them, so display dimensions fall back to the target width
    # (height omitted) — exactly the graceful path for an unreadable file.
    %w[thumb small medium large xl].each do |v|
      FileUtils.touch(File.join(@variants_dir, "photo-#{v}.jpg"))
    end
  end

  teardown do
    %w[thumb small medium large xl].each do |v|
      FileUtils.rm_f(File.join(@variants_dir, "photo-#{v}.jpg"))
    end
  end

  def transform(html, post_url: "/posts/x")
    NewsletterImageTransformer.transform(html, site_url: SITE, post_url: post_url)
  end

  def picture(variant: "medium")
    %(<picture>) +
      %(<source srcset="#{BASE}-small.webp 400w, #{BASE}-large.webp 1200w" type="image/webp">) +
      %(<source srcset="#{BASE}-small.jpg 400w, #{BASE}-large.jpg 1200w">) +
      %(<img src="#{BASE}-#{variant}.jpg" alt="a photo">) +
      %(</picture>)
  end

  def gallery(cols:, n: cols, carousel: false)
    cls = carousel ? "gallery gallery-carousel" : "gallery"
    attr = carousel ? " data-gallery-carousel" : ""
    html = +%(<div class="#{cls}"#{attr}><div class="gallery-row gallery-col-#{cols}">)
    n.times { html << %(<div class="gallery-item"><button class="gallery-zoom-link" popovertarget="z">#{picture}</button></div>) }
    html << %(</div></div>)
    html
  end

  # ── The core bug: srcset/<picture> never survive to email ──────────────────

  test "standalone picture collapses to a single img with no srcset or source" do
    out = transform(picture)
    assert_not_includes out, "<source"
    assert_not_includes out, "srcset"
    assert_not_includes out, "<picture"
    assert_equal 1, Nokogiri::HTML.fragment(out).css("img").length
  end

  test "standalone image is made absolute and uses the large (2x of 600) variant" do
    out = transform(picture(variant: "medium"))
    assert_includes out, "#{SITE}/media/", "src must be absolute"
    assert_includes out, "#{BASE}-large.jpg"
  end

  test "picks the next variant down when the preferred one is missing" do
    # The variant ladder is contiguous: a source too small for large never
    # produced xl either, so both are absent and medium is the real fallback.
    FileUtils.rm_f(File.join(@variants_dir, "photo-large.jpg"))
    FileUtils.rm_f(File.join(@variants_dir, "photo-xl.jpg"))
    out = transform(picture)
    assert_includes out, "#{BASE}-medium.jpg", "should fall to the next available rung"
    assert_not_includes out, "#{BASE}-large.jpg"
  end

  # ── Galleries are dropped entirely (deferred to the variant epic) ──────────

  test "a grid gallery is removed from the email completely" do
    out = transform(gallery(cols: 3, n: 9))
    frag = Nokogiri::HTML.fragment(out)
    assert_equal 0, frag.css("img").length, "no gallery images should remain"
    assert_not_includes out, "gallery"
    assert_not_includes out, "<table"
  end

  test "a carousel gallery is removed from the email completely" do
    out = transform(gallery(cols: 3, n: 4, carousel: true))
    assert_equal 0, Nokogiri::HTML.fragment(out).css("img").length
    assert_not_includes out, "gallery"
  end

  test "removing a gallery takes its lightbox/popover markup with it" do
    out = transform(gallery(cols: 2))
    assert_not_includes out, "popover"
    assert_not_includes out, "gallery-zoom"
    assert_not_includes out, "<button"
    assert_not_includes out, "srcset"
  end

  test "a standalone image survives even when a gallery is also present" do
    html = "#{picture}#{gallery(cols: 3, n: 6)}"
    out = transform(html)
    frag = Nokogiri::HTML.fragment(out)
    assert_equal 1, frag.css("img").length, "only the standalone image should remain"
    assert_includes out, "#{BASE}-large.jpg"
    assert_not_includes out, "gallery"
  end

  # ── Email-safe sizing ──────────────────────────────────────────────────────

  test "images carry max-width:100% and height:auto for fluid scaling" do
    out = transform(picture)
    img = Nokogiri::HTML.fragment(out).at_css("img")
    assert_includes img["style"], "max-width:100%"
    assert_includes img["style"], "height:auto"
  end

  # ── Robustness ─────────────────────────────────────────────────────────────

  test "a non-variant image src is left alone but made absolute" do
    out = transform(%(<picture><img src="/media/images/raw-upload.jpg" alt="x"></picture>))
    assert_includes out, "#{SITE}/media/images/raw-upload.jpg"
  end

  test "blank html is returned untouched" do
    assert_equal "", transform("")
  end
end