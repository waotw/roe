# frozen_string_literal: true

require "test_helper"

# libvips' untrusted loaders are what CVE-2026-66066 turns into an arbitrary
# file read. Roe doesn't use Active Storage variants, so the Rails patch doesn't
# cover it — Roe drives libvips itself, and blocking those loaders is the fix.
#
# The blocking is switched on by an environment variable rather than a call,
# because ruby-vips is `require: false` and loaded lazily at the point of use;
# libvips picks the variable up when it initialises. These tests guard the
# mechanism, since a silently-unset variable looks exactly like a safe system.
class VipsBlockUntrustedTest < ActiveSupport::TestCase
  test "the initializer switches blocking on" do
    assert_equal "1", ENV["VIPS_BLOCK_UNTRUSTED"],
      "config/initializers/vips_block_untrusted.rb should have set this at boot"
  end

  test "an explicit opt-out is respected" do
    original = ENV["VIPS_BLOCK_UNTRUSTED"]
    ENV["VIPS_BLOCK_UNTRUSTED"] = "0"

    load Rails.root.join("config/initializers/vips_block_untrusted.rb")

    assert_equal "0", ENV["VIPS_BLOCK_UNTRUSTED"], "||= must not clobber a deliberate 0"
  ensure
    ENV["VIPS_BLOCK_UNTRUSTED"] = original
  end

  # libvips is optional: an install without it must still boot. The initializer
  # therefore must not require ruby-vips, only set the variable.
  test "the initializer does not load ruby-vips" do
    source = File.read(Rails.root.join("config/initializers/vips_block_untrusted.rb"))

    assert_no_match(/^\s*require\s+["']ruby-vips["']/, source,
      "requiring vips at boot would break installs that don't have libvips")
    assert_match(/ENV\["VIPS_BLOCK_UNTRUSTED"\]/, source)
  end

  test "the container sets it too, for anything that skips the Rails boot" do
    dockerfile = File.read(Rails.root.join("Dockerfile"))

    assert_match(/ENV VIPS_BLOCK_UNTRUSTED="1"/, dockerfile)
  end

  # Guard the version floor the mitigation needs: block_untrusted arrived in
  # libvips 8.13 / ruby-vips 2.2.1 and raises on anything older.
  test "the installed libvips supports blocking" do
    skip "libvips not installed" unless ImageVariantGenerator.available?

    require "ruby-vips"
    assert Vips.respond_to?(:block_untrusted),
      "ruby-vips >= 2.2.1 is required for the mitigation"

    major, minor = Vips.version_string.to_s.split(".").first(2).map(&:to_i)
    assert (major > 8 || (major == 8 && minor >= 13)),
      "libvips >= 8.13 is required to block untrusted loaders (found #{Vips.version_string})"
  end

  # Blocking must not break the formats Roe actually handles, or variant
  # generation quietly stops working.
  test "the formats Roe generates still load and save with blocking on" do
    skip "libvips not installed" unless ImageVariantGenerator.available?

    require "ruby-vips"
    image = Vips::Image.black(24, 12)

    %w[.png .jpg .webp].each do |ext|
      Dir.mktmpdir do |dir|
        path = File.join(dir, "sample#{ext}")
        image.write_to_file(path)
        loaded = Vips::Image.new_from_file(path)

        assert_equal 24, loaded.width, "#{ext} should still round-trip"
      end
    end
  end
end
