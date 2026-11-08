require "test_helper"

class ContentLayoutTest < ActiveSupport::TestCase
  # These tests are about what a site's own layouts do, so content layouts
  # are on; the off state has its own tests.
  setup { SiteConfig.stubs(:content_layouts?).returns(true) }

  def shape(layout)
    layout.blocks.map { |b| [ b.role, b.classes, b.rows.map { |r| [ r.classes, r.parts ] } ] }
  end

  test "one box per line is one part per row, in order" do
    layout = ContentLayout.parse("article", "[title]\n[subtitle]\n[body]\n")
    assert_equal [ [ "title" ], [ "subtitle" ], [ "body" ] ], layout.rows.map(&:parts)
    assert_empty layout.warnings
  end

  test "boxes on one line are one row; spaces in a name are underscores" do
    layout = ContentLayout.parse("article", "[title] [feed links]\n[Date]  [author]\n[body]\n")
    assert_equal [ %w[title feed_links], %w[date author], [ "body" ] ], layout.rows.map(&:parts)
  end

  test "blank lines make blocks: header, groups, content, footer" do
    layout = ContentLayout.parse("podcast", "[title]\n\n[date]\n\n[player]\n[body]\n\n[subscribe]\n\n[episodes]\n")
    assert_equal %i[header group content group footer], layout.blocks.map(&:role)
  end

  test "several blank lines count as one, and leading or trailing ones are ignored" do
    layout = ContentLayout.parse("article", "\n\n[title]\n\n\n\n[body]\n\n\n")
    assert_equal %i[header content], layout.blocks.map(&:role)
  end

  test "a layout that starts with the body has no header; one that ends with it has no footer" do
    assert_equal %i[content footer], ContentLayout.parse("a", "[body]\n\n[subscribe]\n").blocks.map(&:role)
    assert_equal %i[header content], ContentLayout.parse("a", "[title]\n\n[body]\n").blocks.map(&:role)
    assert_equal %i[content], ContentLayout.parse("a", "[body]\n").blocks.map(&:role)
  end

  test "name: on a block's first line names the block; on a row, the row" do
    layout = ContentLayout.parse("article", "post-header:\npost-meta: [date] [author]\n\nhero wide:\n[body]\n")
    assert_equal [
      [ :header, [ "post-header" ], [ [ [ "post-meta" ], %w[date author] ] ] ],
      [ :content, %w[hero wide], [ [ [], [ "body" ] ] ] ]
    ], shape(layout)
    assert_empty layout.warnings
  end

  test "tidy indents every named row when most already are, using their indent" do
    text = "post-header:\n  [title]\n[subtitle]\n  [date]\n\n[body]\n"
    assert_equal "post-header:\n  [title]\n  [subtitle]\n  [date]\n\n[body]\n", ContentLayout.tidy(text)
    assert_equal "top:\n\t[title]\n\t[date]\n\n[body]\n", ContentLayout.tidy("top:\n\t[title]\n[date]\n\n[body]\n")
  end

  test "tidy flattens named rows when most aren't indented" do
    text = "post-header:\n[title]\n[subtitle]\n  [date]\n\n[body]\n"
    assert_equal "post-header:\n[title]\n[subtitle]\n[date]\n\n[body]\n", ContentLayout.tidy(text)
  end

  test "tidy puts names and unnamed blocks at the left edge and empties blank lines" do
    text = "  post-header:\n  [title]\n   \n  [body]\n"
    assert_equal "post-header:\n  [title]\n\n[body]\n", ContentLayout.tidy(text)
  end

  test "tidy leaves a layout with no named block alone" do
    text = "  [title]\n\n[body]\n"
    assert_equal text, ContentLayout.tidy(text)
  end

  test "tidy doesn't change what a layout draws" do
    Dir[File.join(ContentLayout::ROE_DIR, "*#{ContentLayout::EXT}")].each do |path|
      text = File.read(path)
      assert_equal text, ContentLayout.tidy(text), "#{File.basename(path)} is already tidy"
      messy = text.lines.each_with_index.map { |l, i| i.odd? ? l.sub(/\A +/, "") : l }.join
      assert_equal shape(ContentLayout.parse("x", text)), shape(ContentLayout.parse("x", ContentLayout.tidy(messy)))
    end
  end

  test "indenting is ignored, so a block's rows can sit under its name" do
    flat = ContentLayout.parse("article", "post-header:\npost-meta: [date] [author]\n[image]\n\n[body]\n")
    indented = ContentLayout.parse("article", "post-header:\n  post-meta: [date] [author]\n\t[image]\n\n[body]\n")
    assert_equal shape(flat), shape(indented)
    assert_empty indented.warnings
  end

  test "a name on its own line below the first is skipped, with a warning" do
    layout = ContentLayout.parse("article", "[title]\nmeta:\n[body]\n")
    assert_equal [ [] ], layout.blocks.map(&:classes)
    assert_match(/first line of a block/, layout.warnings.join)
  end

  test "a line that isn't boxes is skipped, with a warning naming it" do
    layout = ContentLayout.parse("article", "Hello there\n# Heading\n[title]\n[body]\n- subtitle\n")
    assert_equal %w[title body], layout.parts
    assert_equal 3, layout.warnings.size
    assert_match(/Line 1 isn't a row of \[boxes\]/, layout.warnings.first)
  end

  test "a layout without body gets it at the end, with a warning" do
    layout = ContentLayout.parse("article", "[title]\n[subtitle]\n")
    assert_equal %w[title subtitle body], layout.parts
    assert_equal %i[header content], layout.blocks.map(&:role)
    assert_match(/no \[body\]/, layout.warnings.join)
  end

  test "a second body is skipped" do
    layout = ContentLayout.parse("article", "[body]\n\n[body]\n")
    assert_equal %w[body], layout.parts
    assert_match(/already/, layout.warnings.join)
  end

  test "boxes and class names that aren't plain names are skipped" do
    layout = ContentLayout.parse("article", "[../../etc/passwd] [title]\n\"><script: [date]\n[body]\n")
    assert_equal %w[title date body], layout.parts, "a bad class is left off; its row still shows"
    assert_equal 2, layout.warnings.size
  end

  test "Roe ships a layout for every post type and record type" do
    (Post::POST_TYPES.keys.map(&:to_s) + %w[page podcast-page music-page product documentation]).each do |type|
      next if type == "music" && !Post::POST_TYPES.key?(:music)

      layout = ContentLayout.find(type)
      assert layout, "no layout for #{type}"
      assert_equal :roe, layout.source
      assert_empty layout.warnings, "#{type}: #{layout.warnings.join}"
    end
  end

  test "the site's copy wins over Roe's" do
    with_site_layout("article", "[body]\n[title]\n") do
      layout = ContentLayout.find("article")
      assert_equal :site, layout.source
      assert_equal %w[body title], layout.parts
    end
  end

  test "an edit to the site's copy is picked up" do
    with_site_layout("article", "[body]\n") do |path|
      assert_equal %w[body], ContentLayout.find("article").parts
      File.write(path, "[title]\n[body]\n[subtitle]\n")
      File.utime(Time.now + 5, Time.now + 5, path)
      assert_equal %w[title body subtitle], ContentLayout.find("article").parts
    end
  end

  test "layout: in a post's metadata picks another layout" do
    with_site_layout("announcement", "[title]\n[body]\n") do
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
