require "test_helper"
require "tmpdir"
require "fileutils"

module SiteSync
  # Phase 0 of the variant-generation rework: image variants are a
  # rebuildable cache (each side regenerates them on-demand from the
  # originals), so the Ledger must NOT track them — otherwise every
  # lazily-generated variant on one side shows up as phantom drift
  # against the other. This pins that exclusion.
  class LedgerVariantsExclusionTest < ActiveSupport::TestCase
    def setup
      @dir = Dir.mktmpdir("ledger-variants")
    end

    def teardown
      FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
    end

    def write(relpath, content = "x")
      full = File.join(@dir, relpath)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, content)
    end

    def manifest
      Ledger.new(site_path: @dir).current_manifest
    end

    test "the original image is tracked but its variants subtree is not" do
      write("media/images/photo.jpg", "original")
      write("media/images/variants/photo-small.jpg", "variant")
      write("media/images/variants/photo-small.webp", "variant")
      write("media/images/variants/photo-xl.jpg", "variant")

      keys = manifest.keys
      assert_includes keys, "media/images/photo.jpg"
      refute_includes keys, "media/images/variants/photo-small.jpg"
      refute_includes keys, "media/images/variants/photo-small.webp"
      assert(keys.none? { |k| k.include?("/variants/") },
             "no variant path should ever appear in the sync manifest")
    end
  end
end
