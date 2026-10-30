require "test_helper"
require_relative "../video_test_helpers"

# Phones and cameras name their files clip.MOV and photo.JPG. A
# `Dir.glob("**/*.{mov,mp4}")` pattern finds those on a Mac, whose disk
# ignores case, and misses them on the Linux live site. There, content sync
# read img_0085.MOV as deleted, removed its media record, and removing the
# record deleted the four web versions Site Sync had just sent. The next
# sync saw them missing and sent them again.
#
# These tests make Dir.glob match case the way Linux does, so they catch
# that here on a Mac too.
class MediaExtensionCaseTest < ActiveSupport::TestCase
  include VideoTestHelpers

  setup { setup_video_dir }
  teardown { teardown_video_dir }

  # Dir.glob as a case-sensitive disk would answer it: the real result,
  # minus anything the pattern only matched by ignoring case. Switched on
  # only inside the block.
  module CaseSensitiveGlob
    def glob(pattern, *args, **opts, &blk)
      return super unless Thread.current[:case_sensitive_glob]

      found = super(pattern, *args, **opts).select do |path|
        File.fnmatch(pattern.to_s, path, File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_DOTMATCH)
      end
      blk ? found.each(&blk) : found
    end
  end
  Dir.singleton_class.prepend(CaseSensitiveGlob)

  def with_case_sensitive_glob
    Thread.current[:case_sensitive_glob] = true
    yield
  ensure
    Thread.current[:case_sensitive_glob] = nil
  end

  test "files_with_extensions finds files whatever the case of their extension" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "deep", "clip.mp4")) # a folder, not a file
      %w[a.MOV b.mov deep/c.Jpg d.txt].each do |rel|
        FileUtils.mkdir_p(File.dirname(File.join(root, rel)))
        File.write(File.join(root, rel), "x")
      end

      found = RoeSitePaths.files_with_extensions(root, %w[mov .jpg mp4]).map { |p| p.delete_prefix("#{root}/") }
      assert_equal %w[a.MOV b.mov deep/c.Jpg], found.sort
    end
  end

  test "content sync keeps a .MOV video and its web versions on a case-sensitive disk" do
    web = fake_variants("zz-case-check.MOV")
    source = VideoVariantGenerator.normalize_path(web)
    variants = VideoVariantGenerator.all_variant_paths(source).select { |p| File.exist?(p) }
    assert_equal 3, variants.size # poster, 720p, manifest
    Medium.create!(file_path: web, media_type: "video")

    with_case_sensitive_glob { ContentSync.new.send(:sync_media) }

    assert Medium.exists?(file_path: web), "the .MOV's media record was removed as if the file were gone"
    variants.each { |path| assert File.exist?(path), "#{File.basename(path)} was deleted" }
  end

  test "image variant pruning still counts a .JPG original" do
    images = File.join(RoeSitePaths::SITE_PATH, "media", "images")
    original = File.join(images, "zz-case-check.JPG")
    FileUtils.mkdir_p(images)
    File.binwrite(original, "x")

    found = with_case_sensitive_glob do
      RoeSitePaths.files_with_extensions(images, ImageVariantGenerator::IMAGE_EXTENSIONS)
    end
    assert_includes found, original
  ensure
    FileUtils.rm_f(original)
  end

  # The pattern that caused this, kept out of app code for media.
  test "no media lookup in app code uses a case-sensitive extension pattern" do
    offenders = Dir.glob(Rails.root.join("app", "**", "*.rb")).flat_map do |file|
      File.readlines(file).each_with_index.filter_map do |line, i|
        next if line.lstrip.start_with?("#")
        "#{file.delete_prefix("#{Rails.root}/")}:#{i + 1}" if line.match?(/\*\.\{(jpe?g|png|mp[34]|mov|webm)\b[a-z0-9,]*\}/i)
      end
    end
    assert_empty offenders, "use RoeSitePaths.files_with_extensions so .MOV / .JPG are found on Linux too"
  end
end
