require "test_helper"
require "tmpdir"

class FilesImporterNavTest < ActiveSupport::TestCase
  test "extractor picks the shared site nav, deduped, index preferred" do
    Dir.mktmpdir do |root|
      # A simple sidebar-style nav and a deeply-nested one; the shared one wins.
      shared = %(<nav><ul>
        <li><a href="/feed.xml">RSS Feed</a></li>
        <li><a href="/archive.html">Archive</a></li>
        <li><a href="/about.html">About</a></li>
      </ul></nav>)
      File.write(File.join(root, "index.html"), "<html><body>#{shared}<main>home</main></body></html>")
      File.write(File.join(root, "about.html"), "<html><body>#{shared}<main>about</main></body></html>")
      # a one-off nav on a stray page shouldn't win
      File.write(File.join(root, "weird.html"), %(<html><body><nav><a href="/x">X</a></nav></body></html>))

      nav = FilesImporter::NavExtractor.extract(root)
      assert_equal 3, nav.links.size
      assert_equal({ text: "RSS Feed", href: "/feed.xml" }, nav.links.first)
      assert_includes nav.sources, "index.html"
    end
  end

  test "extractor collects links from a deeply nested nav, ignoring noise" do
    Dir.mktmpdir do |root|
      html = %(<html><body><nav class="x" id="nav">
        <div><div><div class="dot"></div><a href="/">About</a></div>
        <div><div class="dot"></div><a href="/writing">Writing</a></div></div>
      </nav></body></html>)
      File.write(File.join(root, "index.html"), html)
      nav = FilesImporter::NavExtractor.extract(root)
      assert_equal [ { text: "About", href: "/" }, { text: "Writing", href: "/writing" } ], nav.links
    end
  end

  test "extractor returns nil when there's no nav" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, "index.html"), "<html><body><main>no nav here</main></body></html>")
      assert_nil FilesImporter::NavExtractor.extract(root)
    end
  end

  test "writer formats header (inline, separators) and sidebar (bullet list)" do
    links = [ { text: "Home", href: "/" }, { text: "About", href: "/about.html" } ]

    header = FilesImporter::NavWriter.header_markdown(links)
    assert_includes header, "[Home](/) **|**"
    assert_includes header, "[About](/about.html)"
    assert_not header.include?("[About](/about.html) **|**"), "last link has no trailing separator"

    sidebar = FilesImporter::NavWriter.sidebar_markdown(links)
    assert_includes sidebar, "position: left"
    assert_includes sidebar, "- [Home](/)"
    assert_includes sidebar, "- [About](/about.html)"
  end
end
