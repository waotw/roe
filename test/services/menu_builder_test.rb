require "test_helper"

# Turning an imported header's link list into a menu collection: find the
# list, guess a page per link, keep non-pages as inline links, rewrite only
# those lines.
class MenuBuilderTest < ActiveSupport::TestCase
  setup { @created = [] }
  teardown { @created.each { |f| File.delete(f) if File.exist?(f) } }

  def make_page(url_name, title: nil)
    meta = { "title" => title || url_name.tr("-", " ").capitalize, "url_name" => url_name, "status" => "published" }
    slug = ContentWriter.new.write(kind: :page, filename: url_name, metadata: meta, body: "x")
    @created << File.join(RoeSitePaths::SITE_PAGES_PATH, "#{slug}.md")
  end

  IMPORTED = <<~MD
    # My Site

    - [RSS Feed](/feed.xml)
    - [Archive](/archive.html)
    - [Podcast](/audio.html)
    - [About](/about.html)
    - [X](https://x.com/me)

    Some text under the nav.
  MD

  test "find_list returns the contiguous run of link lines and where it sits" do
    found = MenuBuilder.find_list(IMPORTED)
    assert_equal 2, found[:start]
    assert_equal 6, found[:finish]
    assert_equal 5, found[:lines].size
  end

  test "find_list is nil when there are no link lines" do
    assert_nil MenuBuilder.find_list("# Just a heading\n\nand text")
  end

  test "guesses by path, then link text, then title; outside links and unknowns stay links" do
    make_page("mb-archive")
    make_page("mb-podcast", title: "Podcast")
    make_page("mb-about")

    lines = [
      "- [Archive](/mb-archive.html)",   # path
      "- [Podcast](/audio.html)",        # title (path doesn't resolve; text 'podcast' != 'mb-podcast')
      "- [Mb about](/whatever)",         # text slug → mb-about
      "- [RSS Feed](/feed.xml)",         # nothing
      "- [X](https://x.com/me)"          # outside
    ]
    rows = MenuBuilder.rows_for(lines)

    assert_equal [ "mb-archive", :path ],  [ rows[0].url_name, rows[0].confidence ]
    assert_equal [ "mb-podcast", :title ], [ rows[1].url_name, rows[1].confidence ]
    assert_equal [ "mb-about", :text ],    [ rows[2].url_name, rows[2].confidence ]
    assert_equal [ nil, :none ],           [ rows[3].url_name, rows[3].confidence ]
    assert_equal [ nil, :none ],           [ rows[4].url_name, rows[4].confidence ]

    assert_equal "[RSS Feed](/feed.xml)", rows[3].entry
    assert_equal "mb-archive", rows[0].entry
  end

  test "convert replaces only the list, keeping text above and below" do
    out = MenuBuilder.convert(IMPORTED,
      entries: [ "[RSS Feed](/feed.xml)", "archive", "podcast", "about", "[X](https://x.com/me)" ],
      collection: "nav")

    assert_includes out, "# My Site"
    assert_includes out, "Some text under the nav."
    assert_not_includes out, "- [Archive]"
    assert_includes out, "```collection\ncollection: nav\ntemplate: menu\norder: [RSS Feed](/feed.xml), archive, podcast, about, [X](https://x.com/me)\n```"
  end

  test "convert leaves content alone when there is no list" do
    text = "nothing to see"
    assert_equal text, MenuBuilder.convert(text, entries: [ "a" ], collection: "nav")
  end

  test "the converted block renders as a menu with pages and links in order" do
    make_page("mb-about")
    out = MenuBuilder.convert("- [About](/mb-about.html)\n- [Feed](/feed.xml)",
      entries: [ "mb-about", "[Feed](/feed.xml)" ], collection: "nav")

    html = LayoutMarkdown.render(out)
    assert_equal [ "/mb-about", "/feed.xml" ], html.scan(/<a href="([^"]+)"/).flatten
  end
end
