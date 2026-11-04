require "test_helper"

class ContentLayoutTest < ActiveSupport::TestCase
  test "a plain list is one part per group, in order" do
    layout = ContentLayout.parse("article", "- title\n- subtitle\n- body\n")
    assert_equal [ [ "title" ], [ "subtitle" ], [ "body" ] ], layout.groups
    assert_empty layout.warnings
  end

  test "[a, b] is one group" do
    layout = ContentLayout.parse("article", "- [title, feed_links]\n- [date, author]\n- body\n")
    assert_equal [ %w[title feed_links], %w[date author], [ "body" ] ], layout.groups
  end

  test "front matter is read as settings and doesn't become a part" do
    layout = ContentLayout.parse("article", "---\ndate_format: long\n---\n- title\n- body\n")
    assert_equal({ "date_format" => "long" }, layout.settings)
    assert_equal %w[title body], layout.parts
  end

  test "comments and blank lines are ignored" do
    layout = ContentLayout.parse("article", "# The article layout\n\n- title\n\n- body\n")
    assert_equal %w[title body], layout.parts
  end

  test "a layout without body gets it at the end, with a warning" do
    layout = ContentLayout.parse("article", "- title\n- subtitle\n")
    assert_equal %w[title subtitle body], layout.parts
    assert_match(/no body/, layout.warnings.join)
  end

  test "a file that isn't a list shows only the body, with a warning" do
    layout = ContentLayout.parse("article", "title: yes\n")
    assert_equal [ "body" ], layout.parts
    assert_match(/isn't a list/, layout.warnings.join)
  end

  test "broken YAML shows only the body, with a warning" do
    layout = ContentLayout.parse("article", "- [title\n- body")
    assert_equal [ "body" ], layout.parts
    assert_match(/couldn't be read/, layout.warnings.join)
  end

  test "names that aren't part names are skipped" do
    layout = ContentLayout.parse("article", "- title\n- \"../../etc/passwd\"\n- { a: 1 }\n- body\n")
    assert_equal %w[title body], layout.parts
    assert_equal 2, layout.warnings.size
  end

  test "Roe ships a layout for every post type and record type" do
    (Post::POST_TYPES.keys.map(&:to_s) + %w[page product documentation]).each do |type|
      next if type == "music" && !Post::POST_TYPES.key?(:music)

      layout = ContentLayout.find(type)
      assert layout, "no layout for #{type}"
      assert_equal :roe, layout.source
      assert_empty layout.warnings, "#{type}: #{layout.warnings.join}"
    end
  end

  test "the site's copy wins over Roe's" do
    with_site_layout("article", "- body\n- title\n") do
      layout = ContentLayout.find("article")
      assert_equal :site, layout.source
      assert_equal %w[body title], layout.parts
    end
  end

  test "an edit to the site's copy is picked up" do
    with_site_layout("article", "- body\n") do |path|
      assert_equal %w[body], ContentLayout.find("article").parts
      File.write(path, "- title\n- body\n- subtitle\n")
      File.utime(Time.now + 5, Time.now + 5, path)
      assert_equal %w[title body subtitle], ContentLayout.find("article").parts
    end
  end

  test "layout: in a post's metadata picks another layout" do
    with_site_layout("announcement", "- title\n- body\n") do
      post = Post.new(metadata: { "post_type" => "article", "layout" => "announcement" })
      assert_equal "announcement", ContentLayout.for(post).name
    end
  end

  test "layout: naming a missing file falls back to the type's" do
    post = Post.new(metadata: { "post_type" => "podcast", "layout" => "post" })
    assert_equal "podcast", ContentLayout.for(post).name
  end

  # Jekyll imports carry `layout: page`; that mustn't strip a post's header.
  test "layout: can't pick the page, product or documentation layout" do
    post = Post.new(metadata: { "post_type" => "article", "layout" => "page" })
    assert_equal "article", ContentLayout.for(post).name
  end

  test "layout: with a path in it is ignored" do
    post = Post.new(metadata: { "post_type" => "article", "layout" => "../../config/master" })
    assert_equal "article", ContentLayout.for(post).name
  end

  private

  def with_site_layout(name, text)
    path = ContentLayout.site_path(name)
    existed = File.exist?(path)
    original = File.read(path) if existed
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
    yield path
  ensure
    existed ? File.write(path, original) : FileUtils.rm_f(path)
  end
end
