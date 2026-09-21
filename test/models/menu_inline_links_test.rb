require "test_helper"

# A menu's `order:` list takes url_names and, in the same positions, inline
# markdown links — so one nav can hold pages, a feed and an outside site.
class MenuInlineLinksTest < ActiveSupport::TestCase
  setup { @created = [] }
  teardown { @created.each { |f| File.delete(f) if File.exist?(f) } }

  def make_page(name, extra = {})
    meta = { "title" => name.tr("-", " ").capitalize, "url_name" => name, "status" => "published" }.merge(extra)
    slug = ContentWriter.new.write(kind: :page, filename: name, metadata: meta, body: "x")
    @created << File.join(RoeSitePaths::SITE_PAGES_PATH, "#{slug}.md")
  end

  def menu(order)
    LayoutMarkdown.render("```collection\ntemplate: menu\nsource: pages\ncollection: mixnav\norder: #{order}\n```")
  end

  def hrefs(html)
    html.scan(/<a href="([^"]+)">([^<]+)<\/a>/)
  end

  test "an inline link renders in place among pages, in order" do
    make_page("mix-about")
    make_page("mix-contact")

    links = hrefs(menu("mix-about, [RSS Feed](/feed.xml), mix-contact, [x](https://x.com/me)"))

    assert_equal [ "/mix-about", "/feed.xml", "/mix-contact", "https://x.com/me" ], links.map(&:first)
    assert_equal "RSS Feed", links[1].last
    assert_equal "x", links[3].last
  end

  test "a comma inside a link's text does not split the entry" do
    make_page("mix-home")
    links = hrefs(menu("[Hi, there](/hello), mix-home"))

    assert_equal 2, links.size
    assert_equal [ "/hello", "Hi, there" ], links.first
  end

  test "link text and URL are escaped" do
    html = menu(%q{[<b>bold</b>](/x?a=1&b=2)})
    assert_includes html, "&lt;b&gt;bold&lt;/b&gt;"
    assert_includes html, "/x?a=1&amp;b=2"
    assert_not_includes html, "<b>bold</b>"
  end

  test "tagged pages still follow the ordered list, and an inline link never counts as a duplicate" do
    make_page("mix-listed")
    make_page("mix-tagged", "collection" => "mixnav")

    links = hrefs(menu("[Feed](/feed.xml), mix-listed"))
    assert_equal [ "/feed.xml", "/mix-listed", "/mix-tagged" ], links.map(&:first)
  end

  test "a url_name that doesn't resolve is skipped, inline links around it survive" do
    links = hrefs(menu("[A](/a), no-such-page, [B](/b)"))
    assert_equal [ "/a", "/b" ], links.map(&:first)
  end
end
