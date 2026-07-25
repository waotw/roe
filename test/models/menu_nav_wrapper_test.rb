require "test_helper"

# A `template: menu` collection is site navigation when it renders in a layout
# file (header/footer/sidebar) → wrap in <nav>; in a page body it's a content
# list → bare <ul>.
class MenuNavWrapperTest < ActiveSupport::TestCase
  setup { @created = [] }
  teardown { @created.each { |f| File.delete(f) if File.exist?(f) } }

  def make_page(name, extra = {})
    meta = { "title" => name.tr("-", " "), "url_name" => name, "status" => "published" }.merge(extra)
    slug = ContentWriter.new.write(kind: :page, filename: name, metadata: meta, body: "x")
    @created << File.join(RoeSitePaths::SITE_PAGES_PATH, "#{slug}.md")
  end

  MENU = "```collection\ntemplate: menu\nsource: pages\ncollection: mynav\n```"

  test "a menu in a layout file wraps in <nav>, labeled by the collection name" do
    make_page("nav-about", "collection" => "mynav")

    html = LayoutMarkdown.render(MENU)

    assert_includes html, "<nav", "layout menu is a nav landmark"
    assert_includes html, %(aria-label="mynav"), "labeled by the (invisible) collection name"
    assert_includes html, "collection-menu"
  end

  test "the same menu in a page body stays a bare <ul> — no <nav>" do
    make_page("nav-about-2", "collection" => "mynav")
    slug = ContentWriter.new.write(
      kind: :post, filename: "menu-host",
      metadata: { "title" => "Host", "url_name" => "menu-host", "status" => "published" },
      body: MENU
    )
    @created << File.join(RoeSitePaths::SITE_POSTS_PATH, "#{slug}.md")
    post = Post.find_by("json_extract(metadata, '$.url_name') = ?", slug)

    html = post.to_html

    assert_includes html, "collection-menu"
    assert_not_includes html, "<nav", "a body menu is a content list, not a landmark"
  end
end
