# frozen_string_literal: true

require "test_helper"

class MediaReferenceRewriterTest < ActiveSupport::TestCase
  def setup
    @old = "/media/images/old-name.jpg"
    @new = "/media/images/new-name.jpg"
    @posts_dir = File.join(RoeSitePaths::SITE_PATH, "posts")
    FileUtils.mkdir_p(@posts_dir)
    @site_yml = SiteConfig::SITE_FILE
    FileUtils.mkdir_p(File.dirname(@site_yml))
    @site_yml_existed = File.exist?(@site_yml)
    @site_yml_backup = File.read(@site_yml) if @site_yml_existed
  end

  def teardown
    Dir.glob(File.join(@posts_dir, "rewriter-*.md")).each { |f| File.delete(f) }
    if @site_yml_existed
      File.write(@site_yml, @site_yml_backup)
    elsif File.exist?(@site_yml)
      File.delete(@site_yml)
    end
  end

  test "rewrites a media path in a post's file and body, and re-syncs the DB" do
    file = File.join(@posts_dir, "rewriter-body.md")
    File.write(file, "---\ntitle: Post\n---\n\nSee ![pic](#{@old}) here.\n")
    Post.create_or_update_from_file(file)

    count = MediaReferenceRewriter.rewrite(@old, @new)

    assert_equal 1, count
    assert_includes File.read(file), @new
    refute_includes File.read(file), @old
    assert_includes Post.find_by(file_path: file).content, @new
  end

  test "rewrites a media path in a post's frontmatter metadata" do
    file = File.join(@posts_dir, "rewriter-meta.md")
    File.write(file, "---\ntitle: Post\nimage: \"#{@old}\"\n---\n\nBody.\n")
    Post.create_or_update_from_file(file)

    MediaReferenceRewriter.rewrite(@old, @new)

    assert_equal @new, Post.find_by(file_path: file).metadata["image"]
  end

  test "rewrites a product referenced via a relative file_path" do
    # Regression: Product stores file_path relative to SITE_PATH, so the
    # rewriter's File.file? check failed and products were skipped.
    products_dir = File.join(RoeSitePaths::SITE_PATH, "products")
    FileUtils.mkdir_p(products_dir)
    file = File.join(products_dir, "rewriter-album.md")
    File.write(file, "---\ntitle: Album\nprice: 10\nimage: \"#{@old}\"\n---\n\nBuy it.\n")
    Product.create_or_update_from_file(file)

    begin
      count = MediaReferenceRewriter.rewrite(@old, @new)

      assert_equal 1, count
      assert_includes File.read(file), @new
      refute_includes File.read(file), @old
    ensure
      File.delete(file) if File.exist?(file)
    end
  end

  test "rewrites a media path in a config file" do
    File.write(@site_yml, { "logo" => @old, "title" => "Site" }.to_yaml)

    count = MediaReferenceRewriter.rewrite(@old, @new)

    assert_equal 1, count
    assert_includes File.read(@site_yml), @new
    refute_includes File.read(@site_yml), @old
  end

  test "returns zero and touches nothing when the path is unreferenced" do
    file = File.join(@posts_dir, "rewriter-none.md")
    File.write(file, "---\ntitle: Post\n---\n\nNo media here.\n")
    Post.create_or_update_from_file(file)

    assert_equal 0, MediaReferenceRewriter.rewrite(@old, @new)
  end

  test "no-op when old and new are the same" do
    assert_equal 0, MediaReferenceRewriter.rewrite(@old, @old)
  end
end
