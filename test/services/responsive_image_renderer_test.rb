require "test_helper"

# How a source image path becomes markup. The renderer reads each variant's
# ACTUAL pixel width (via FastImage — no native image lib) to build an
# honest, de-duplicated srcset, and serves it whenever variants exist on
# disk regardless of libvips. Fixtures are minimal hand-built PNG headers
# (FastImage only reads the header), so these tests need no libvips.
class ResponsiveImageRendererTest < ActiveSupport::TestCase
  DIR      = File.join(RoeSitePaths::SITE_PATH, "media", "images", "rr_test").freeze
  WEB_PATH = "/media/images/rr_test/photo.png".freeze

  setup { FileUtils.mkdir_p(File.join(DIR, "variants")) }
  teardown { FileUtils.rm_rf(DIR) }

  # A valid PNG *header* of the given size — enough for FastImage.size.
  def png_bytes(width, height)
    ihdr = [ width, height ].pack("N2") + "\x08\x02\x00\x00\x00".b
    "\x89PNG\r\n\x1a\n".b + [ ihdr.bytesize ].pack("N") + "IHDR".b + ihdr + ("\x00" * 4).b
  end

  def write_png(path, width, height = width)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, png_bytes(width, height))
  end

  # Source of `source_width`, plus a variant set with explicit per-variant
  # actual widths (native PNG header + an existence-only .webp sibling).
  def setup_variants(source_width:, variants:)
    write_png(File.join(DIR, "photo.png"), source_width, source_width)
    variants.each do |name, w|
      native = File.join(DIR, "variants", "photo-#{name}.png")
      write_png(native, w, w)
      File.write(native.sub(/\.png\z/, ".webp"), "") # existence only
    end
  end

  test "serves <picture> from existing variants even when libvips is unavailable" do
    setup_variants(source_width: 2000, variants: { thumb: 150, small: 400, medium: 800, large: 1200, xl: 1800 })
    ImageVariantGenerator.stubs(:available?).returns(false)

    html = ResponsiveImageRenderer.render(WEB_PATH, alt: "A photo")

    assert_includes html, "<picture>"
    assert_includes html, 'type="image/webp"'
    assert_includes html, 'alt="A photo"'
  end

  test "srcset advertises each variant at its ACTUAL pixel width" do
    setup_variants(source_width: 2000, variants: { thumb: 150, small: 400, medium: 800, large: 1200, xl: 1800 })
    ImageVariantGenerator.stubs(:available?).returns(false)

    html = ResponsiveImageRenderer.render(WEB_PATH)

    { small: 400, medium: 800, large: 1200, xl: 1800 }.each do |name, width|
      assert_includes html, "photo-#{name}.png #{width}w"
      assert_includes html, "photo-#{name}.webp #{width}w"
    end
  end

  test "uses the actual width, not the declared limit, for a capped variant" do
    # 1000px source: large caps at 1000 (its limit is 1200), xl is skipped.
    setup_variants(source_width: 1000, variants: { thumb: 150, small: 400, medium: 800, large: 1000 })
    ImageVariantGenerator.stubs(:available?).returns(false)

    html = ResponsiveImageRenderer.render(WEB_PATH)

    assert_includes html, "photo-large.png 1000w"  # honest, actual width
    refute_includes html, "photo-large.png 1200w"  # not the declared limit
  end

  test "dedupes variants that share an actual width (small source)" do
    # 200px source over-provisioned: every limit variant is capped to 200.
    setup_variants(source_width: 200, variants: { thumb: 150, small: 200, medium: 200, large: 200, xl: 200 })
    ImageVariantGenerator.stubs(:available?).returns(false)

    html = ResponsiveImageRenderer.render(WEB_PATH)

    assert_includes html, "<picture>"
    assert_includes html, "photo-small.png 200w" # the one kept
    refute_includes html, "photo-medium.png"      # deduped out
    refute_includes html, "photo-large.png"
    refute_includes html, "photo-xl.png"
  end

  test "falls back to the original <img> when no variants exist and no libvips" do
    write_png(File.join(DIR, "photo.png"), 2000)
    ImageVariantGenerator.stubs(:available?).returns(false)

    html = ResponsiveImageRenderer.render(WEB_PATH)

    refute_includes html, "<picture>"
    assert_includes html, "<img"
    assert_includes html, %(src="#{WEB_PATH}")
  end

  test "queues generation and shows the original when variants missing but libvips present" do
    write_png(File.join(DIR, "photo.png"), 2000)
    ImageVariantGenerator.stubs(:available?).returns(true)
    ImageVariantGenerator.expects(:queue!).with(WEB_PATH).at_least_once

    html = ResponsiveImageRenderer.render(WEB_PATH)

    refute_includes html, "<picture>"
    assert_includes html, "<img"
  end

  test "serves a <picture> from just the baseline and queues the rest to enrich" do
    # Only the baseline (small + xl) on disk — the middle sizes aren't built yet.
    setup_variants(source_width: 2000, variants: { small: 400, xl: 1800 })
    ImageVariantGenerator.stubs(:available?).returns(true)
    ImageVariantGenerator.expects(:queue!).with(WEB_PATH).at_least_once # enrich next render

    html = ResponsiveImageRenderer.render(WEB_PATH)

    assert_includes html, "<picture>", "baseline is enough to serve a responsive picture"
    assert_includes html, "photo-small.png 400w"
    assert_includes html, "photo-xl.png 1800w"
    refute_includes html, "photo-medium.png", "middle sizes aren't built yet"
  end

  test "static build generates the full needed set synchronously, not via a queued job" do
    write_png(File.join(DIR, "photo.png"), 2000)
    ImageVariantGenerator.stubs(:available?).returns(true)
    ImageVariantGenerator.expects(:generate_variants).at_least_once   # inline
    ImageVariantGenerator.expects(:queue!).never                      # never async during a bake

    Current.static_generation = true
    begin
      ResponsiveImageRenderer.render(WEB_PATH)
    ensure
      Current.static_generation = nil
    end
  end
end
