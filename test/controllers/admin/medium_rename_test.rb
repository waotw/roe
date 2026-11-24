# frozen_string_literal: true

require "test_helper"

class Admin::MediumRenameTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    @images_dir = File.join(RoeSitePaths::SITE_PATH, "media", "images")
    @variants_dir = File.join(@images_dir, "variants")
    @posts_dir = File.join(RoeSitePaths::SITE_PATH, "posts")
    FileUtils.mkdir_p(@variants_dir)
    FileUtils.mkdir_p(@posts_dir)
  end

  def teardown
    FileUtils.rm_rf(@images_dir)
    Dir.glob(File.join(@posts_dir, "rename-*.md")).each { |f| File.delete(f) }
  end

  test "renames the file, its variants, and rewrites references" do
    old_web = "/media/images/old-pic.jpg"
    File.write(File.join(@images_dir, "old-pic.jpg"), "JPGDATA")
    File.write(File.join(@variants_dir, "old-pic-medium.jpg"), "VARIANT")
    File.write(File.join(@variants_dir, "old-pic-medium.webp"), "WEBP")
    medium = Medium.create!(file_path: old_web, media_type: "images")

    post_file = File.join(@posts_dir, "rename-user.md")
    File.write(post_file, "---\ntitle: Uses It\n---\n\n![pic](#{old_web})\n")
    Post.create_or_update_from_file(post_file)

    patch rename_admin_medium_path(medium), params: { new_filename: "new-pic" }

    # File and variants moved
    assert File.exist?(File.join(@images_dir, "new-pic.jpg"))
    refute File.exist?(File.join(@images_dir, "old-pic.jpg"))
    assert File.exist?(File.join(@variants_dir, "new-pic-medium.jpg"))
    assert File.exist?(File.join(@variants_dir, "new-pic-medium.webp"))
    refute File.exist?(File.join(@variants_dir, "old-pic-medium.jpg"))

    # Medium record and the referencing post both updated
    assert_equal "/media/images/new-pic.jpg", medium.reload.file_path
    assert_includes File.read(post_file), "/media/images/new-pic.jpg"
    refute_includes File.read(post_file), old_web
  end

  test "a renamed video keeps its web versions, manifest and chosen poster" do
    video_dir = File.join(RoeSitePaths::SITE_PATH, "media", "video")
    vdir = File.join(video_dir, "variants")
    FileUtils.mkdir_p(vdir)
    File.write(File.join(video_dir, "zz-old-clip.mp4"), "MP4DATA")
    File.write(File.join(vdir, "zz-old-clip-720p.mp4"), "720")
    File.write(File.join(vdir, "zz-old-clip-poster.jpg"), "JPG")
    File.write(File.join(vdir, "zz-old-clip-video.json"), JSON.pretty_generate(
      "source" => { "path" => "/media/video/zz-old-clip.mp4", "size" => 7 },
      "poster" => "/media/video/variants/zz-old-clip-poster.jpg",
      "poster_from" => "frame", "poster_at" => 12.5,
      "renditions" => [ { "name" => "720p", "path" => "/media/video/variants/zz-old-clip-720p.mp4" } ]
    ))
    medium = Medium.create!(file_path: "/media/video/zz-old-clip.mp4", media_type: "video")

    patch rename_admin_medium_path(medium), params: { new_filename: "zz-new-clip" }

    %w[zz-new-clip-720p.mp4 zz-new-clip-poster.jpg zz-new-clip-video.json].each do |name|
      assert File.exist?(File.join(vdir, name)), "#{name} should have moved"
    end
    assert_empty Dir.glob(File.join(vdir, "zz-old-clip-*"))

    manifest = JSON.parse(File.read(File.join(vdir, "zz-new-clip-video.json")))
    assert_equal "/media/video/zz-new-clip.mp4", manifest.dig("source", "path")
    assert_equal "/media/video/variants/zz-new-clip-poster.jpg", manifest["poster"]
    assert_equal "/media/video/variants/zz-new-clip-720p.mp4", manifest.dig("renditions", 0, "path")
    assert_equal [ "frame", 12.5 ], manifest.values_at("poster_from", "poster_at")
    assert_equal({ from: "frame", at: 12.5 }, VideoVariantGenerator.poster_choice(manifest))
  ensure
    Dir.glob(File.join(video_dir, "zz-*")).each { |f| File.delete(f) }
    Dir.glob(File.join(vdir, "zz-*")).each { |f| File.delete(f) }
  end

  test "rejects renaming onto an existing filename" do
    File.write(File.join(@images_dir, "a.jpg"), "A")
    File.write(File.join(@images_dir, "b.jpg"), "B")
    medium = Medium.create!(file_path: "/media/images/a.jpg", media_type: "images")

    patch rename_admin_medium_path(medium), params: { new_filename: "b" }

    assert File.exist?(File.join(@images_dir, "a.jpg")), "original should be untouched"
    assert_equal "/media/images/a.jpg", medium.reload.file_path
  end
end
