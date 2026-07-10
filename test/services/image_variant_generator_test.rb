require "test_helper"

# Generation needs libvips to actually resize, so these SKIP when it's
# unavailable. They pin down:
#   * each NEEDED variant is produced at the right dimensions.
#   * a small source skips redundant larger sizes (never upscaled).
#   * existing variants are NEVER overwritten — manual/synced files are
#     preserved, only missing ones are filled in.
#   * force: true rebuilds everything (the Regenerate Variants path).
class ImageVariantGeneratorTest < ActiveSupport::TestCase
  DIR = File.join(RoeSitePaths::SITE_PATH, "media", "images", "ivg_test").freeze

  setup do
    skip "libvips not installed" unless ImageVariantGenerator.available?
    require "vips"
    FileUtils.mkdir_p(DIR)
  end

  teardown { FileUtils.rm_rf(DIR) }

  def make_source(name, width, height)
    path = File.join(DIR, name)
    ((Vips::Image.black(width, height, bands: 3) + [ 120, 90, 60 ]).cast("uchar"))
      .write_to_file(path)
    path
  end

  def dims(path)
    img = Vips::Image.new_from_file(path)
    [ img.width, img.height ]
  end

  def variant(src, name)
    ImageVariantGenerator.variant_path_for(src, name)
  end

  test "generates each needed variant at the correct dimensions (large source)" do
    src = make_source("big.png", 2000, 2000)
    assert ImageVariantGenerator.generate_variants(src)

    assert_equal [ 150, 150 ], dims(variant(src, :thumb)), "thumb is a 150x150 square crop"
    assert_operator dims(variant(src, :small)).max,  :<=, 400
    assert_operator dims(variant(src, :medium)).max, :<=, 800
    assert_operator dims(variant(src, :large)).max,  :<=, 1200
    assert_operator dims(variant(src, :xl)).max,     :<=, 1800
    assert File.exist?(variant(src, :medium).sub(/\.png\z/, ".webp")), "webp sibling exists"
  end

  test "skips redundant variants for a small (200x200) source" do
    src = make_source("small.png", 200, 200)
    assert ImageVariantGenerator.generate_variants(src)

    # Only thumb + small are worth producing: medium/large/xl would all be
    # identical 200px (no upscaling), so they're skipped entirely.
    assert_equal [ 200, 200 ], dims(variant(src, :small)), "small caps at the source size"
    assert_equal [ 150, 150 ], dims(variant(src, :thumb))
    refute File.exist?(variant(src, :medium)), "medium is redundant → skipped"
    refute File.exist?(variant(src, :large)),  "large is redundant → skipped"
    refute File.exist?(variant(src, :xl)),     "xl is redundant → skipped"
  end

  test "never overwrites an existing variant (preserves manual/synced files)" do
    src = make_source("keep.png", 1000, 1000)
    sentinel = variant(src, :small)
    FileUtils.mkdir_p(File.dirname(sentinel))
    File.write(sentinel, "MANUAL") # not a real image — proves it's untouched

    ImageVariantGenerator.generate_variants(src) # force: false (default)

    assert_equal "MANUAL", File.read(sentinel), "an existing variant must be preserved"
    assert File.exist?(variant(src, :medium)), "a missing needed variant is still generated"
  end

  test "force: true rebuilds existing variants" do
    src = make_source("force.png", 1000, 1000)
    sentinel = variant(src, :small)
    FileUtils.mkdir_p(File.dirname(sentinel))
    File.write(sentinel, "MANUAL")

    ImageVariantGenerator.generate_variants(src, force: true)

    refute_equal "MANUAL", File.read(sentinel), "force must overwrite"
    assert_operator dims(sentinel).max, :<=, 400, "rebuilt small variant is correctly sized"
  end

  # ---------------------------------------------------------------- baseline

  test "only: restricts generation to the requested variant (the upload baseline)" do
    src = make_source("baseline.png", 2000, 2000)
    assert ImageVariantGenerator.generate_variants(src, only: [ :small ])

    assert File.exist?(variant(src, :small)), "the baseline (small) is generated"
    assert File.exist?(variant(src, :small).sub(/\.png\z/, ".webp")), "small webp too"
    refute File.exist?(variant(src, :medium)), "medium is NOT built for a baseline-only run"
    refute File.exist?(variant(src, :large))
    refute File.exist?(variant(src, :xl))
    refute File.exist?(variant(src, :thumb)), "thumb is NOT part of the baseline"
  end

  test "queue_baseline! targets exactly BASELINE_VARIANTS" do
    assert_equal [ :small ], ImageVariantGenerator::BASELINE_VARIANTS
  end

  test "variants_exist? respects only:, and a baseline run is not the full ladder" do
    src = make_source("partial.png", 2000, 2000)
    ImageVariantGenerator.generate_variants(src, only: [ :small ])

    assert ImageVariantGenerator.variants_exist?(src, only: [ :small ]), "baseline present"
    refute ImageVariantGenerator.variants_exist?(src), "the full ladder is not present"
  end

  test "a baseline-only run does not stamp the Medium row complete; the full run does" do
    src = make_source("stamp.png", 2000, 2000)
    medium = Medium.create!(file_path: "/media/images/ivg_test/stamp.png",
                            media_type: "images", uploaded_at: Time.current)

    ImageVariantGenerator.generate_variants(src, only: [ :small ])
    refute_equal "complete", medium.reload.variants_status,
                 "baseline isn't the full set — must not mark the row complete"

    ImageVariantGenerator.generate_variants(src) # fill the full ladder
    assert_equal "complete", medium.reload.variants_status
  end
end
