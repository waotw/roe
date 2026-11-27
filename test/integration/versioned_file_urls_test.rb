require "test_helper"

# Public pages carry ?v=<version> on every file URL, so a file can be cached
# for a year and still be fetched again the moment it changes.
class VersionedFileUrlsTest < ActionDispatch::IntegrationTest
  IMAGE = "/media/images/versioned-test.webp"

  setup do
    @written = []
    write(IMAGE, "IMAGE")
  end

  teardown do
    @written.each { |path| FileUtils.rm_f(path) }
    FileValidators.year_cache = false
  end

  def write(url_path, content)
    absolute = File.join(RoeSitePaths::SITE_PATH, url_path.delete_prefix("/"))
    FileUtils.mkdir_p(File.dirname(absolute))
    File.binwrite(absolute, content)
    @written << absolute
    absolute
  end

  def version(url_path = IMAGE)
    FileVersions.version_for_url(url_path)
  end

  def rewrite(html, hosts: [ "www.example.com" ])
    VersionedFileUrls::Rewriter.new(hosts).rewrite(html)
  end

  # ── What gets a version ───────────────────────────────────────────────────

  test "an image gets its file's version" do
    assert_equal %(<img src="#{IMAGE}?v=#{version}" alt="a">), rewrite(%(<img src="#{IMAGE}" alt="a">))
  end

  test "the version changes when the file does" do
    before = version
    write(IMAGE, "A DIFFERENT IMAGE")
    refute_equal before, version
  end

  test "srcset candidates each get a version and keep their widths" do
    html = %(<img srcset="#{IMAGE} 400w, #{IMAGE} 800w">)
    assert_equal %(<img srcset="#{IMAGE}?v=#{version} 400w, #{IMAGE}?v=#{version} 800w">), rewrite(html)
  end

  test "an existing query is kept, and an old v is replaced" do
    assert_equal %(<audio src="#{IMAGE}?token=abc&amp;v=#{version}">),
                 rewrite(%(<audio src="#{IMAGE}?token=abc">))
    assert_equal %(<link href="#{IMAGE}?v=#{version}">), rewrite(%(<link href="#{IMAGE}?v=12345">))
  end

  test "a fragment stays at the end" do
    assert_equal %(<video src="#{IMAGE}?v=#{version}#t=10">), rewrite(%(<video src="#{IMAGE}#t=10">))
  end

  test "url() in style attributes and style blocks" do
    assert_equal %(<div style="background: url('#{IMAGE}?v=#{version}')">),
                 rewrite(%(<div style="background: url('#{IMAGE}')">))
    assert_equal "<style>@font-face { src: url(#{IMAGE}?v=#{version}); }</style>",
                 rewrite("<style>@font-face { src: url(#{IMAGE}); }</style>")
  end

  test "an absolute URL on this site gets a version; another site's doesn't" do
    assert_equal %(<meta content="https://www.example.com#{IMAGE}?v=#{version}">),
                 rewrite(%(<meta content="https://www.example.com#{IMAGE}">))
    assert_equal %(<meta content="https://cdn.example.org#{IMAGE}">),
                 rewrite(%(<meta content="https://cdn.example.org#{IMAGE}">))
    assert_equal %(<meta content="https://Blog.Example.net#{IMAGE}?v=#{version}">),
                 rewrite(%(<meta content="https://Blog.Example.net#{IMAGE}">), hosts: [ "localhost", "blog.example.net" ]),
                 "the site's own address from site.yml counts, as og:image uses it"
  end

  test "theme CSS, site JS, fonts and system images" do
    font = write("/system/assets/fonts/versioned-test.woff2", "FONT")
    logo = write("/system/assets/images/versioned-test.png", "PNG")
    theme = write("/theme/versioned-test.css", "a {}")

    html = rewrite(<<~HTML)
      <link href="/theme/versioned-test.css" rel="stylesheet">
      <script src="/javascript/search.js"></script>
      <link rel="preload" href="/system/fonts/versioned-test.woff2">
      <img src="/system/images/versioned-test.png">
    HTML

    assert_includes html, "/theme/versioned-test.css?v=#{FileVersions.version_for(theme)}"
    assert_includes html, "/javascript/search.js?v=#{version("/javascript/search.js")}"
    assert_includes html, "/system/fonts/versioned-test.woff2?v=#{FileVersions.version_for(font)}"
    assert_includes html, "/system/images/versioned-test.png?v=#{FileVersions.version_for(logo)}"
  end

  # ── What's left alone ─────────────────────────────────────────────────────

  test "a missing file, a page link and other attributes are left alone" do
    html = %(<img src="/media/images/nope.webp" title="#{IMAGE}"><a href="/posts/hello">x</a>)
    assert_equal html, rewrite(html)
  end

  test "scripts and text, including code samples, are left alone" do
    html = <<~HTML
      <script>var src = "#{IMAGE}"; document.write('<img src="#{IMAGE}">');</script>
      <pre><code>&lt;img src="#{IMAGE}"&gt; and url(#{IMAGE})</code></pre>
      <p>Put it at #{IMAGE}.</p>
    HTML
    assert_equal html, rewrite(html)
  end

  test "a filename with spaces still gets a version" do
    spaced = "/media/images/versioned test.webp"
    write(spaced, "SPACED")
    assert_equal %(<img src="#{spaced}?v=#{version(spaced)}">), rewrite(%(<img src="#{spaced}">))
  end

  # ── Pages ─────────────────────────────────────────────────────────────────

  test "a public page is sent with versioned file URLs" do
    Page.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "pages", "versioned.md"),
      content: "![a](#{IMAGE})",
      metadata: { "title" => "Versioned", "url_name" => "versioned", "status" => "published" }
    )

    get "/versioned"
    assert_response :success
    assert_includes response.body, "#{IMAGE}?v=#{version}"
    assert_match %r{/theme/[\w-]+\.css\?v=\w+}, response.body, "the theme link too"
  end

  test "admin pages and non-HTML responses pass through untouched" do
    html = %(<img src="#{IMAGE}">)
    app = VersionedFileUrls.new(->(_env) { [ 200, { "content-type" => "text/html" }, [ html ] ] })
    _, _, body = app.call(Rack::MockRequest.env_for("/admin/media"))
    assert_equal html, body.join

    json = VersionedFileUrls.new(->(_env) { [ 200, { "content-type" => "application/json" }, [ html ] ] })
    _, _, body = json.call(Rack::MockRequest.env_for("/search.json"))
    assert_equal html, body.join
  end

  test "it sits inside StaticSiteMiddleware, so static-mode pages pass by" do
    names = Rails.application.middleware.map { |m| m.klass.to_s }
    assert_operator names.index("StaticSiteMiddleware"), :<, names.index("VersionedFileUrls")
  end

  # ── The year cache ────────────────────────────────────────────────────────

  test "on live, the current version is cached for a year; an old one is checked" do
    FileValidators.year_cache = true

    get "#{IMAGE}?v=#{version}"
    assert_response :success
    assert_equal "max-age=31536000, public, immutable", response.headers["Cache-Control"]

    get "#{IMAGE}?v=000000000000"
    assert_equal "no-cache, public", response.headers["Cache-Control"]

    get IMAGE
    assert_equal "no-cache, public", response.headers["Cache-Control"], "no ?v=, the normal check"
  end

  test "local never uses the year cache" do
    get "#{IMAGE}?v=#{version}"
    assert_equal "no-cache, public", response.headers["Cache-Control"]
  end

  test "paid media never gets the year cache" do
    FileValidators.year_cache = true
    audio = "/media/audio/versioned-paid.mp3"
    write(audio, "PAID")
    Medium.find_or_create_by!(file_path: audio) { |m| m.media_type = "audio" }
    Post.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "versioned-paid.md"),
      content: "Body.",
      metadata: { "title" => "Paid", "url_name" => "versioned-paid", "status" => "published",
                  "audience" => "paid", "audio" => audio }
    )
    member = Member.create!(email: "vpaid@example.com", name: "Paid", tier: :paid, status: :active)

    get "#{audio}?token=#{member.reload.media_token}&v=#{version(audio)}"
    assert_response :success
    assert_equal "no-cache, private", response.headers["Cache-Control"]
  end
end
