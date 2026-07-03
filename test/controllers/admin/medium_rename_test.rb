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

  test "rejects renaming onto an existing filename" do
    File.write(File.join(@images_dir, "a.jpg"), "A")
    File.write(File.join(@images_dir, "b.jpg"), "B")
    medium = Medium.create!(file_path: "/media/images/a.jpg", media_type: "images")

    patch rename_admin_medium_path(medium), params: { new_filename: "b" }

    assert File.exist?(File.join(@images_dir, "a.jpg")), "original should be untouched"
    assert_equal "/media/images/a.jpg", medium.reload.file_path
  end
end
