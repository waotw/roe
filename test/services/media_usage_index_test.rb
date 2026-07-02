# frozen_string_literal: true

require "test_helper"

class MediaUsageIndexTest < ActiveSupport::TestCase
  include Rails.application.routes.url_helpers

  def setup
    @site_yml = SiteConfig::SITE_FILE
    FileUtils.mkdir_p(File.dirname(@site_yml))
    @site_yml_existed = File.exist?(@site_yml)
    @site_yml_backup = File.read(@site_yml) if @site_yml_existed
  end

  def teardown
    if @site_yml_existed
      File.write(@site_yml, @site_yml_backup)
    elsif File.exist?(@site_yml)
      File.delete(@site_yml)
    end
  end

  test "indexes media referenced in post content and metadata" do
    post = Post.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "p1.md"),
      content: "Here is ![pic](/media/images/inline.jpg) in the body.",
      metadata: { "title" => "My Post", "image" => "/media/images/cover.png" }
    )

    index = MediaUsageIndex.new.build

    inline = index["/media/images/inline.jpg"]
    cover  = index["/media/images/cover.png"]

    assert_equal 1, inline.size
    assert_equal "post", inline.first[:kind]
    assert_equal "My Post", inline.first[:label]
    assert_includes inline.first[:url], edit_admin_post_path(post)
    assert_includes inline.first[:url], "highlight="
    assert_equal 1, cover.size
  end

  test "indexes a metadata media path containing spaces and parens" do
    path = "/media/video/CLOSER_ a dance video (Tegan and Sara).mp4"
    post = Post.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "vid.md"),
      content: "A video post.",
      metadata: { "title" => "Video Post", "video" => path }
    )

    usages = MediaUsageIndex.new.build[path]

    assert_equal 1, usages.size, "the full spaced/paren path should match exactly"
    assert_equal "post", usages.first[:kind]
    assert_equal "post", usages.first[:type]
    assert_includes usages.first[:url], edit_admin_post_path(post)
  end

  test "usages carry a compact type label per source" do
    Page.create!(file_path: File.join(RoeSitePaths::SITE_PATH, "pages", "p.md"),
                 content: "![x](/media/images/pg.png)", metadata: { "title" => "P" })

    assert_equal "page", MediaUsageIndex.new.build["/media/images/pg.png"].first[:type]
  end

  test "indexes media referenced in a page (not just posts)" do
    page = Page.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "pages", "about.md"),
      content: "![diagram](/media/images/diagram.png)",
      metadata: { "title" => "About" }
    )

    usages = MediaUsageIndex.new.build["/media/images/diagram.png"]

    assert_equal 1, usages.size
    assert_equal "page", usages.first[:kind]
    assert_includes usages.first[:url], edit_admin_page_path(page)
  end

  test "indexes media referenced in a config file and marks it global" do
    File.write(@site_yml, { "logo" => "/media/images/logo.svg", "title" => "Site" }.to_yaml)

    usages = MediaUsageIndex.new.build["/media/images/logo.svg"]

    assert_equal 1, usages.size
    usage = usages.first
    assert_equal "config", usage[:kind]
    assert usage[:global], "config references should be flagged global"
    assert_includes usage[:label], "logo"
    assert_includes usage[:url], "focus=logo"
  end

  test "an unreferenced path returns an empty list" do
    assert_empty MediaUsageIndex.new.build["/media/images/nobody-uses-me.jpg"]
  end

  test "a file referenced from multiple sources lists all of them" do
    Post.create!(file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "a.md"),
                 content: "![x](/media/shared.png)", metadata: { "title" => "A" })
    File.write(@site_yml, { "social_image" => "/media/shared.png" }.to_yaml)

    usages = MediaUsageIndex.new.build["/media/shared.png"]

    kinds = usages.map { |u| u[:kind] }.sort
    assert_equal %w[config post], kinds
  end
end
