require "test_helper"

# Animated GIFs only animate as the original file — libvips resizes the
# first frame only, so every variant is a still. The generator must know
# which GIFs are animated (with and without libvips), make nothing but the
# admin thumb for them, and the renderer must serve the original.
class AnimatedGifTest < ActiveSupport::TestCase
  DIR = File.join(RoeSitePaths::SITE_PATH, "media", "images", "gif_test").freeze

  setup { FileUtils.mkdir_p(DIR) }
  teardown { FileUtils.rm_rf(DIR) }

  # A hand-built GIF89a: 1×1 logical screen, 2-colour global table, then
  # `frames` minimal image descriptors, each with an empty 1-bit LZW stream.
  # Includes a graphic control extension and a NETSCAPE loop extension
  # before the frames, so the byte scan has extension blocks to skip.
  def gif_bytes(frames:)
    out = +"GIF89a".b
    out << [ 1, 1 ].pack("v2") << "\x80\x00\x00".b            # screen; GCT flag, 2 colours
    out << "\x00\x00\x00\xFF\xFF\xFF".b                       # global colour table
    out << "\x21\xFF\x0BNETSCAPE2.0\x03\x01\x00\x00\x00".b   # loop extension
    frames.times do
      out << "\x21\xF9\x04\x00\x0A\x00\x00\x00".b             # graphic control ext
      out << "\x2C".b << [ 0, 0, 1, 1 ].pack("v4") << "\x00".b # image descriptor
      out << "\x02\x02\x44\x01\x00".b                         # LZW min code 2, 2 bytes, terminator
    end
    out << "\x3B".b
  end

  def write_gif(name, frames:)
    path = File.join(DIR, name)
    File.binwrite(path, gif_bytes(frames: frames))
    path
  end

  # ── Detection ────────────────────────────────────────────────────────

  test "byte scan tells a two-frame GIF from a one-frame GIF" do
    assert ImageVariantGenerator.gif_frame_count_at_least_two?(write_gif("anim.gif", frames: 2))
    assert_not ImageVariantGenerator.gif_frame_count_at_least_two?(write_gif("still.gif", frames: 1))
  end

  test "byte scan rejects things that aren't GIFs" do
    path = File.join(DIR, "not.gif")
    File.binwrite(path, "\x89PNG\r\n\x1a\n".b)
    assert_not ImageVariantGenerator.gif_frame_count_at_least_two?(path)
  end

  test "animated? is false for non-GIF extensions and missing files without reading them" do
    assert_not ImageVariantGenerator.animated?(File.join(DIR, "photo.png"))
    assert_not ImageVariantGenerator.animated?(File.join(DIR, "missing.gif"))
  end

  test "animated? agrees between libvips and the byte scan" do
    anim  = write_gif("anim.gif", frames: 3)
    still = write_gif("still.gif", frames: 1)

    ImageVariantGenerator.stubs(:available?).returns(false)
    assert ImageVariantGenerator.animated?(anim)
    assert_not ImageVariantGenerator.animated?(still)

    ImageVariantGenerator.unstub(:available?)
    if ImageVariantGenerator.available?
      assert ImageVariantGenerator.animated?(anim)
      assert_not ImageVariantGenerator.animated?(still)
    end
  end

  # A GIF libvips itself wrote — a real multi-frame file rather than the
  # hand-built one above, so the libvips path is exercised on something
  # produced by the same library that reads it.
  test "animated? reads a libvips-written animated GIF through libvips" do
    skip "libvips not installed" unless ImageVariantGenerator.available?
    require "vips"

    frames = 3.times.map { |i| (Vips::Image.black(20, 20, bands: 3) + [ i * 80, 50, 200 ]).cast("uchar") }
    anim = Vips::Image.arrayjoin(frames, across: 1).copy
    anim.set_type(GObject::GINT_TYPE, "page-height", 20)
    anim.set_type(GObject::GINT_TYPE, "n-pages", 3)
    path = File.join(DIR, "vips-anim.gif")
    anim.write_to_file(path)

    ImageVariantGenerator.expects(:gif_frame_count_at_least_two?).never
    assert ImageVariantGenerator.animated?(path)
    assert_equal [ :thumb ], ImageVariantGenerator.send(:variant_names_for, path)
  end

  # ── Generation ───────────────────────────────────────────────────────

  test "an animated GIF only ever wants the admin thumb" do
    anim = write_gif("anim.gif", frames: 2)
    assert_equal [ :thumb ], ImageVariantGenerator.send(:variant_names_for, anim)
  end

  test "a still GIF is a normal image to the generator" do
    still = write_gif("still.gif", frames: 1)
    ImageVariantGenerator.stubs(:available?).returns(false)
    assert_includes ImageVariantGenerator.send(:variant_names_for, still), :small
  end

  # ── Baseline / admin grid ────────────────────────────────────────────
  #
  # Regression: an animated GIF's only variant is :thumb, so the old
  # baseline_variant_names (which stripped :thumb) returned [] → baseline_ready?
  # was FOREVER false → the admin card stayed variants-pending and the browser
  # polled it every 1.5s, re-injecting the card (which also broke tab filtering).
  # The thumb IS the animated GIF's baseline preview.
  test "an animated GIF's baseline is its thumb, not empty" do
    anim = write_gif("anim.gif", frames: 2)
    assert_equal [ :thumb ], ImageVariantGenerator.baseline_variant_names(anim)
  end

  test "an animated GIF becomes baseline-ready once its thumb exists" do
    skip "libvips not installed" unless ImageVariantGenerator.available?
    anim = write_gif("anim.gif", frames: 2)

    assert_not ImageVariantGenerator.baseline_exists?(anim), "no thumb yet"
    ImageVariantGenerator.generate_variants("/media/images/gif_test/anim.gif")
    assert ImageVariantGenerator.baseline_exists?(anim), "thumb present → baseline ready"
  end

  test "a still GIF's baseline is the normal small+largest set, not the thumb" do
    still = write_gif("still.gif", frames: 1)
    ImageVariantGenerator.stubs(:available?).returns(false)
    names = ImageVariantGenerator.baseline_variant_names(still)
    assert_includes names, :small
    assert_not_includes names, :thumb
  end

  # ── Rendering ────────────────────────────────────────────────────────

  test "renders an animated GIF as the original file with no srcset" do
    write_gif("anim.gif", frames: 2)
    html = ResponsiveImageRenderer.render("/media/images/gif_test/anim.gif", alt: "wave")

    assert_includes html, 'src="/media/images/gif_test/anim.gif"'
    assert_not_includes html, "srcset"
    assert_not_includes html, "/variants/"
    assert_includes html, 'alt="wave"'
  end

  test "renders an animated GIF as the original even when variants exist on disk" do
    anim = write_gif("anim.gif", frames: 2)
    FileUtils.mkdir_p(File.join(DIR, "variants"))
    %i[thumb small medium].each do |name|
      FileUtils.cp(anim, ImageVariantGenerator.variant_path_for(anim, name))
    end

    html = ResponsiveImageRenderer.render("/media/images/gif_test/anim.gif")
    assert_not_includes html, "/variants/"
  end
end
