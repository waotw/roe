# frozen_string_literal: true

require "test_helper"

# Verifies the web→email image rewrite: no srcset/<picture> (email ignores
# them), galleries become <table>s, URLs go absolute, and variants are chosen
# by context for retina sharpness.
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

  def grid(cols:, n: cols)
    html = +%(<div class="gallery"><div class="gallery-row gallery-col-#{cols}">)
    n.times { html << %(<div class="gallery-item"><button class="gallery-zoom-link" popovertarget="z">#{picture}</button></div>) }
    html << %(</div></div>)
    html
  end

  def carousel(n: 3)
    html = +%(<div class="gallery gallery-carousel" data-gallery-carousel><div class="gallery-track">)
    n.times { |i| html << %(<div class="gallery-item"><button class="gallery-zoom-link" popovertarget="z#{i}">#{picture}</button></div>) }
    html << %(</div><div id="z0" popover class="gallery-zoom"><img src="#{BASE}-xl.jpg"></div></div>)
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

  test "no relative /media URL survives — every image src is absolute" do
    out = transform(grid(cols: 3))
    Nokogiri::HTML.fragment(out).css("img").each do |img|
      assert img["src"].start_with?("#{SITE}/media/"), "relative src left: #{img['src']}"
    end
  end

  # ── Retina variant selection by context ───────────────────────────────────

  test "standalone image uses the large (2x of 600) variant" do
    out = transform(picture(variant: "medium"))
    assert_includes out, "#{BASE}-large.jpg"
  end

  test "grid variant scales with column count" do
    assert_includes transform(grid(cols: 1)), "#{BASE}-large.jpg"   # 1 col -> large
    assert_includes transform(grid(cols: 2)), "#{BASE}-medium.jpg"  # 2 col -> medium
    assert_includes transform(grid(cols: 3)), "#{BASE}-small.jpg"   # 3 col -> small
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

  # ── Galleries become tables, faithful to the column layout ─────────────────

  test "grid gallery becomes a presentation table with one cell per image" do
    out = transform(grid(cols: 3))
    frag = Nokogiri::HTML.fragment(out)
    assert_equal 1, frag.css('table[role="presentation"]').length
    assert_equal 3, frag.css("td.eg-cell").length
    assert_not_includes out, "gallery-row"
  end

  test "column count is read from the class, so a 4-up grid just works" do
    out = transform(grid(cols: 4))
    frag = Nokogiri::HTML.fragment(out)
    assert_equal 4, frag.css("td.eg-cell").length
    assert_equal "25.0%", frag.css("td.eg-cell").first["width"]
    assert_includes out, "#{BASE}-small.jpg"
  end

  test "the zoom lightbox markup is stripped (no popover reaches email)" do
    out = transform(grid(cols: 2))
    assert_not_includes out, "popover"
    assert_not_includes out, "gallery-zoom"
    assert_not_includes out, "<button"
  end

  test "gallery cells link to the post when a post_url is given" do
    out = transform(grid(cols: 2), post_url: "/posts/hello")
    Nokogiri::HTML.fragment(out).css("td.eg-cell").each do |td|
      a = td.at_css("a")
      assert_not_nil a, "cell should wrap its image in a link"
      assert_equal "#{SITE}/posts/hello", a["href"]
    end
  end

  # ── Carousel: first image only ─────────────────────────────────────────────

  test "carousel collapses to only its first image, linked, at large size" do
    out = transform(carousel(n: 4))
    frag = Nokogiri::HTML.fragment(out)
    assert_equal 1, frag.css("img").length, "carousel should show exactly one image"
    assert_includes out, "#{BASE}-large.jpg"
    assert_not_nil frag.at_css("a"), "the one image should link to the post"
    assert_not_includes out, "gallery-track"
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