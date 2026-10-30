require "test_helper"

# A `template: menu` collection emits `data-show-active` on its <ul> ONLY when
# the block sets `show_active:` explicitly. That attribute is how a single menu
# overrides its layout file's highlight default (LayoutHelper#add_active_nav_class):
# a footer menu can opt in, a header menu can opt out. An unspecified menu emits
# nothing and just follows the file default.
class MenuShowActiveTest < ActiveSupport::TestCase
  setup { @created = [] }
  teardown { @created.each { |f| File.delete(f) if File.exist?(f) } }

  def make_page(name)
    meta = { "title" => name.tr("-", " "), "url_name" => name, "status" => "published", "collection" => "mynav" }
    slug = ContentWriter.new.write(kind: :page, filename: name, metadata: meta, body: "x")
    @created << File.join(RoeSitePaths::SITE_PAGES_PATH, "#{slug}.md")
  end

  def menu(extra_line = nil)
    [ "```collection", "template: menu", "source: pages", "collection: mynav", extra_line, "```" ].compact.join("\n")
  end

  test "no show_active line emits no data-show-active attribute" do
    make_page("msa-a")
    html = LayoutMarkdown.render(menu)
    assert_includes html, "collection-menu"
    assert_not_includes html, "data-show-active"
  end

  test "show_active: true emits data-show-active=\"true\"" do
    make_page("msa-b")
    html = LayoutMarkdown.render(menu("show_active: true"))
    assert_includes html, %(data-show-active="true")
  end

  test "show_active: false emits data-show-active=\"false\"" do
    make_page("msa-c")
    html = LayoutMarkdown.render(menu("show_active: false"))
    assert_includes html, %(data-show-active="false")
  end

  test "a non-false value reads as true" do
    make_page("msa-d")
    html = LayoutMarkdown.render(menu("show_active: yes"))
    assert_includes html, %(data-show-active="true")
  end
end
