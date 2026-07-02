# frozen_string_literal: true

require "test_helper"

class PodcastConfigSeederTest < ActiveSupport::TestCase
  def setup
    @artwork_dir = PodcastConfigSeeder::ARTWORK_DIR
    FileUtils.rm_rf(@artwork_dir)
  end

  def teardown
    FileUtils.rm_rf(@artwork_dir)
  end

  # Regression: download_artwork used ARTWORK_DIR.join(filename), but
  # ARTWORK_DIR is a String (File.join) with no #join, so it raised
  # NoMethodError that the rescue swallowed — artwork was silently skipped
  # and never landed in system/assets/images.
  def test_download_artwork_writes_into_system_assets_images
    seeder = PodcastConfigSeeder.new("my-show", { "image_url" => "https://example.com/cover.png" })

    fake_io = StringIO.new("PNGDATA")
    URI.stubs(:open).yields(fake_io)

    filename = seeder.send(:download_artwork)

    assert_equal "my-show-artwork.png", filename
    dest = File.join(@artwork_dir, filename)
    assert File.exist?(dest), "expected artwork written to #{dest}"
    assert_equal "PNGDATA", File.binread(dest)

    # And nothing leaked to the system/ root.
    system_root = File.join(RoeSitePaths::SITE_PATH, "system")
    refute File.exist?(File.join(system_root, filename)), "artwork must not land in system/ root"
  end

  def test_download_artwork_returns_blank_when_no_image_url
    seeder = PodcastConfigSeeder.new("my-show", {})
    assert_equal "", seeder.send(:download_artwork)
  end
end
