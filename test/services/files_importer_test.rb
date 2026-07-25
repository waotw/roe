require "test_helper"

class FilesImporterTest < ActiveSupport::TestCase
  def parser
    @parser ||= FilesImporter::Parser.new
  end

  # ── Markdown parsing ─────────────────────────────────────────────────────
  test "markdown with frontmatter maps known fields and keeps the rest as custom" do
    md = <<~MD
      ---
      title: Hello World
      date: "2024-01-05"
      slug: custom-slug
      tags: [ruby, rails]
      author: Ben
      subtitle: A subtitle
      summary: The summary text
      categories: [tech]
      weird_key: keep me
      ---
      # Heading

      Body text here.
    MD
    doc = parser.parse_markdown(md, "blog/hello.md")

    assert_equal "Hello World", doc.title
    assert_equal "2024-01-05", doc.date
    assert doc.dated
    assert_equal "custom-slug", doc.slug
    assert_equal %w[ruby rails], doc.tags
    assert_equal "Ben", doc.author
    assert_equal "A subtitle", doc.subtitle
    assert_equal "The summary text", doc.excerpt, "summary maps to excerpt"
    assert_equal({ "categories" => [ "tech" ], "weird_key" => "keep me" }, doc.custom, "unmapped keys preserved")
    assert_includes doc.body, "Body text here."
  end

  test "markdown without frontmatter takes its title from the first heading" do
    doc = parser.parse_markdown("# From Heading\n\nText.", "notes/thing.md")
    assert_equal "From Heading", doc.title
    assert_not doc.dated
    assert_nil doc.slug
  end

  test "markdown with neither frontmatter nor heading falls back to a humanized filename" do
    doc = parser.parse_markdown("Just text.", "notes/my-cool-note.md")
    assert_equal "My Cool Note", doc.title
  end

  test "a Jekyll dated filename keeps the exact basename and surfaces the date" do
    doc = parser.parse_markdown("body", "_posts/2024-03-09-launch-day.md")
    assert_equal "2024-03-09-launch-day", doc.basename, "filename preserved exactly"
    assert_equal "2024-03-09", doc.date
    assert doc.dated
  end

  # ── HTML parsing ─────────────────────────────────────────────────────────
  test "html parsing pulls title, description, date, and a chrome-free body" do
    html = <<~HTML
      <html><head>
        <title>My Page</title>
        <meta name="description" content="A short desc">
        <meta property="article:published_time" content="2024-02-01T08:00:00Z">
      </head><body>
        <nav><a href="/">Home</a></nav>
        <main><h1>My Page</h1><p>Hello <strong>world</strong>.</p></main>
        <footer>footer junk</footer>
        <script>var x = 1;</script>
      </body></html>
    HTML
    doc = parser.parse_html(html, "about.html")

    assert_equal "My Page", doc.title
    assert_equal "A short desc", doc.excerpt
    assert_equal "2024-02-01T08:00:00Z", doc.date
    assert_includes doc.body, "Hello **world**."
    assert_not_includes doc.body, "Home", "nav stripped"
    assert_not_includes doc.body, "junk", "footer stripped"
  end

  # --- Episode-like detection ----------------------------------------------
  test "flags episode-like files (audio in frontmatter/body/HTML or a podcast folder)" do
    assert parser.parse_markdown("---\ntitle: X\naudio: https://x/ep.mp3\n---\nbody", "blog/x.md").episode_like, "audio frontmatter"
    assert parser.parse_markdown("body [listen](https://x/ep.mp3)", "notes/y.md").episode_like, "audio link in body"
    assert parser.parse_html("<html><body><main><audio src='/a.mp3'></audio></main></body></html>", "p.html").episode_like, "<audio> tag"
    assert parser.parse_markdown("just text", "podcast/ep1.md").episode_like, "podcast/ folder"
    assert_not parser.parse_markdown("---\ntitle: A\n---\nplain text", "blog/article.md").episode_like, "plain article"
  end

  # ── Classification ───────────────────────────────────────────────────────
  def doc(source_path, type_hint: nil, dated: false)
    FilesImporter::Document.new(
      source_path: source_path, basename: File.basename(source_path, ".*"),
      type_hint: type_hint, dated: dated
    )
  end

  test "classifier: frontmatter hint wins over everything" do
    assert_equal :post, FilesImporter::Classifier.classify(doc("pages/x.md", type_hint: "post"))
    assert_equal :page, FilesImporter::Classifier.classify(doc("_posts/x.md", type_hint: "page"))
  end

  test "classifier: folder conventions" do
    assert_equal :post, FilesImporter::Classifier.classify(doc("_posts/2024-01-05-hi.md"))
    assert_equal :post, FilesImporter::Classifier.classify(doc("blog/my-article.md"))
    assert_equal :page, FilesImporter::Classifier.classify(doc("pages/about.md"))
  end

  test "classifier: Jekyll filename and a bare date lean post" do
    assert_equal :post, FilesImporter::Classifier.classify(doc("misc/2024-01-05-hi.md"))
    assert_equal :post, FilesImporter::Classifier.classify(doc("content/note.md", dated: true))
  end

  test "classifier: a top-level undated file leans page, a buried one is ambiguous" do
    assert_equal :page, FilesImporter::Classifier.classify(doc("about.html"))
    assert_equal :ambiguous, FilesImporter::Classifier.classify(doc("content/random.md"))
  end
end
