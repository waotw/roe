require "test_helper"

class InternalLinksTest < ActiveSupport::TestCase
  setup { @created = [] }
  teardown { @created.each { |f| File.delete(f) if File.exist?(f) } }

  def make(kind, name, status: "published", title: nil, url_name: nil, body: "body")
    meta = { "title" => title || name.titleize, "status" => status, "date" => "2024-01-01" }
    meta["url_name"] = url_name if url_name
    meta["post_type"] = "article" if kind == :post
    slug = ContentWriter.new.write(kind: kind, filename: name, metadata: meta, body: body)
    dir = kind == :post ? RoeSitePaths::SITE_POSTS_PATH : RoeSitePaths::SITE_PAGES_PATH
    path = File.join(dir, "#{slug}.md")
    @created << path
    ContentSync.sync_file(path)
    (kind == :post ? Post : Page).find_by(file_path: RoeSitePaths.normalize(path))
  end

  def html(markdown) = Post.new(file_path: "x.md", content: markdown).to_html.to_s

  test "a wikilink names a file and shows the title, or its own text" do
    make(:post, "il-target", title: "The Target", url_name: "il-target-address")

    assert_includes html("See [[posts/il-target]]."), %(<a href="/posts/il-target-address">The Target</a>)
    assert_includes html("See [[posts/il-target|this one]]."), %(<a href="/posts/il-target-address">this one</a>)
  end

  test "the folder can be left off when only one file has the name; with two it can't" do
    make(:post, "il-solo")
    assert_includes html("[[il-solo]]"), %(href="/posts/il-solo")

    make(:post, "il-twice")
    make(:page, "il-twice")
    assert_equal [ :ambiguous, %w[pages/il-twice posts/il-twice] ], InternalLinks.status("il-twice").then { |s, refs| [ s, refs.sort ] }
    assert_includes html("[[pages/il-twice]]"), %(href="/il-twice")
  end

  test "a Markdown link to a file goes to the item's address, anchor kept" do
    make(:post, "il-md", url_name: "il-md-address")

    assert_includes html("[read](/posts/il-md.md#notes)"), %(<a href="/posts/il-md-address#notes">read</a>)
  end

  test "a link to a draft or to nothing shows as its text" do
    make(:post, "il-draft", status: "draft")
    out = html("[[posts/il-draft|soon]] and [[posts/il-none]] and [gone](/posts/il-none.md)")

    assert_includes out, "soon and posts/il-none and gone"
    assert_not_includes out, "<a"
  end

  test "code is left as written, and the pipe doesn't split a table cell" do
    make(:post, "il-code")
    out = html("`[[posts/il-code]]`\n\n| a | b |\n|---|---|\n| [[posts/il-code|x]] | y |\n")

    assert_includes out, "<code>[[posts/il-code]]</code>"
    assert_includes out, %(<td><a href="/posts/il-code">x</a></td>)
  end

  test "Roe's own docs aren't linkable" do
    assert_not InternalLinks.linkable_ref?("documentation/roe/start")
  end

  test "the markdown check reports a link to nothing, to a draft, and an unclear one" do
    make(:post, "il-check-draft", status: "draft")
    make(:post, "il-check-twice")
    make(:page, "il-check-twice")
    issues = MarkdownDoctor.diagnose("[[posts/il-missing]] [[posts/il-check-draft]] [[il-check-twice]]",
                                     link_status: ->(t) { InternalLinks.status(t) })

    assert_equal %i[broken_internal_link draft_link unclear_internal_link], issues.map { |i| i[:type] }
  end

  # ── Renames ──────────────────────────────────────────────────────────────

  test "renaming a file points links to it at the new name, outside code" do
    target = make(:post, "il-old-name")
    linker = make(:post, "il-linker", body: "[[posts/il-old-name|a]] [[il-old-name]] [b](/posts/il-old-name.md#x)\n\n`[[posts/il-old-name]]`\n")

    count = InternalLinkRewriter.file_renamed("posts/il-old-name", "posts/il-new-name")

    assert_equal 3, count, "three links, in one file"
    body = File.read(linker.file_path)
    assert_includes body, "[[posts/il-new-name|a]] [[posts/il-new-name]] [b](/posts/il-new-name.md#x)"
    assert_includes body, "`[[posts/il-old-name]]`"
    assert target
  end

  test "a new address updates old links written as addresses" do
    linker = make(:post, "il-addr-linker", body: "[old](/posts/il-gone) and [old too](/posts/il-gone#a) and [other](/posts/il-gone-not)\n")

    InternalLinkRewriter.address_changed("/posts/il-gone", "/posts/il-here")

    assert_includes File.read(linker.file_path), "[old](/posts/il-here) and [old too](/posts/il-here#a) and [other](/posts/il-gone-not)"
  end

  # ── Files changed outside Roe ────────────────────────────────────────────

  test "a file renamed outside Roe takes the site's links with it" do
    target = make(:post, "il-ext-old")
    linker = make(:post, "il-ext-linker", body: "[[posts/il-ext-old]] and [x](/posts/il-ext-old.md)\n")
    new_path = File.join(RoeSitePaths::SITE_POSTS_PATH, "il-ext-new.md")
    @created << new_path
    File.rename(target.file_path, new_path)

    ContentWatcher.send(:handle_changes, [], [ new_path ], [ target.file_path ])

    assert_equal target.id, Post.find_by(file_path: RoeSitePaths.normalize(new_path))&.id, "same record, new name"
    assert_includes File.read(linker.file_path), "[[posts/il-ext-new]] and [x](/posts/il-ext-new.md)"
  end

  test "a url_name changed outside Roe updates links written as addresses" do
    target = make(:post, "il-ext-addr", url_name: "il-ext-before")
    linker = make(:post, "il-ext-addr-linker", body: "[old](/posts/il-ext-before)\n")
    File.write(target.file_path, File.read(target.file_path).sub("url_name: \"il-ext-before\"", "url_name: \"il-ext-after\""))

    ContentWatcher.send(:handle_changes, [ target.file_path ], [], [])

    assert_includes File.read(linker.file_path), "[old](/posts/il-ext-after)"
  end

  # Roe wasn't running: nothing saw the change happen, so the sync at start
  # catches up — the same record, found by its text, and links that follow.
  test "changes made while Roe was off are caught up when it starts" do
    renamed = make(:post, "il-off-old", body: "A body only this post has.\n")
    moved = make(:page, "il-off-page", url_name: "il-off-before")
    linker = make(:post, "il-off-linker", body: "[[posts/il-off-old]] and [p](/il-off-before)\n")

    new_path = File.join(RoeSitePaths::SITE_POSTS_PATH, "il-off-new.md")
    @created << new_path
    File.rename(renamed.file_path, new_path)
    File.write(moved.file_path, File.read(moved.file_path).sub("url_name: \"il-off-before\"", "url_name: \"il-off-after\""))

    ContentSync.sync_all

    assert_equal renamed.id, Post.find_by(file_path: RoeSitePaths.normalize(new_path))&.id
    assert_includes File.read(linker.file_path), "[[posts/il-off-new]] and [p](/il-off-after)"
  end

  # ── Metadata fields ──────────────────────────────────────────────────────

  test "links work in Markdown metadata fields, and their plain text is the link's text" do
    make(:post, "il-field", title: "Field Target")

    assert_includes FieldText.html("See [[posts/il-field]]."), %(<a href="/posts/il-field">Field Target</a>)
    assert_includes FieldText.html("See [it](/posts/il-field.md)."), %(<a href="/posts/il-field">it</a>)
    assert_equal "See it and Field Target", FieldText.plain("See [[posts/il-field|it]] and [[il-field]]")
  end

  # ── Two pages at one address ─────────────────────────────────────────────

  test "a page using another page's address is found; products in one group aren't" do
    first = make(:page, "il-clash-a", url_name: "il-clash")
    second = make(:page, "il-clash-b", url_name: "il-clash")

    assert_equal second.id, UrlNameClash.find(Page, "il-clash", except_id: first.id)&.id
    assert_nil UrlNameClash.find(Page, "il-clash-free", except_id: first.id)
  end
end
