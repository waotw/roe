require "test_helper"

class HasMarkdownExtensionsTest < ActiveSupport::TestCase
  class TestModel
    include HasMarkdownExtensions
    include HasInlineFootnotes

    attr_accessor :content

    def initialize(content)
      @content = content
    end

    def to_html(preview: false)
      super(preview: preview)
    end
  end

  def render(content, preview: false)
    TestModel.new(content).to_html(preview: preview)
  end

  # =============================================================================
  # Code Block Protection Tests
  # =============================================================================

  test "preserves triple backtick code blocks" do
    content = MarkdownFixture::CODE_BLOCK_RUBY
    result = render(content)

    assert_match(/def hello/, result)
    assert_match(/puts "Hello, World!"/, result)
  end

  test "preserves 4+ backtick code blocks" do
    content = MarkdownFixture::CODE_BLOCK_FOUR_BACKTICKS
    result = render(content)

    assert_match(/Code with four backticks/, result)
  end

  test "code inside collection blocks is processed as markdown" do
    # NOTE: This is current behavior - nested code blocks inside collection blocks
    # are processed as markdown, not preserved as code. This is a known limitation.
    content = <<~MARKDOWN
      ```collection
      ```ruby
      puts "this should stay as code"
      ```
      ```
    MARKDOWN

    result = render(content)

    # The code is processed, not preserved (current implementation limitation)
    # The collection renders with the code block processed
    assert_match(/<div class="collection list"/, result)
  end

  test "code inside card blocks is processed as markdown" do
    # NOTE: This is current behavior - nested code blocks inside card blocks
    # are processed as markdown, not preserved as code. This is a known limitation.
    content = <<~MARKDOWN
      ```card
      type: aside
      text: "Something"

      ```ruby
      puts "code in card"
      ```
      ```
    MARKDOWN

    result = render(content)

    # The card renders, and code is processed separately (current implementation limitation)
    assert_match(/class="card card-aside"/, result)
  end

  test "code inside gallery blocks prevents gallery processing" do
    # NOTE: This is current behavior - nested code blocks inside gallery blocks
    # prevent the gallery from being recognized. This is a known limitation.
    content = <<~MARKDOWN
      ```gallery
      ```code
      not an image
      ```
      ```
    MARKDOWN

    result = render(content)

    # The gallery block isn't recognized due to nested code (current limitation)
    # Content is processed as regular markdown instead
    refute_match(/class="gallery"/, result)
    assert_match(/<code>/, result)
  end

  test "complex nested structures preserved" do
    content = <<~MARKDOWN
      # Header

      ```card
      type: pullquote
      text: "Quote"
      ```

      Regular paragraph with `inline code`.

      ```ruby
      class Test
        def method
          puts "code"
        end
      end
      ```
    MARKDOWN

    result = render(content)

    assert_match(/class Test/, result)
    assert_match(/inline code/, result)
    assert_match(/Quote/, result)
  end

  # =============================================================================
  # Gallery Tests
  # =============================================================================

  test "manual gallery renders gallery elements" do
    content = MarkdownFixture::GALLERY_SIMPLE
    result = render(content)

    assert_match(/<div class="gallery"/, result)
    assert_match(/<div class="gallery-row gallery-col-3"/, result)
    assert_match(/<img src="mountain.jpg"/, result)
    assert_match(/<img src="ocean.jpg"/, result)
    assert_match(/<img src="forest.jpg"/, result)
  end

  test "manual gallery with multiple images" do
    content = MarkdownFixture::GALLERY_SIMPLE
    result = render(content)

    assert_match(/mountain\.jpg/, result)
    assert_match(/ocean\.jpg/, result)
    assert_match(/forest\.jpg/, result)
  end

  test "manual gallery with captions" do
    content = MarkdownFixture::GALLERY_WITH_CAPTIONS
    result = render(content)

    assert_match(/<figcaption>/, result)
    assert_match(/The majestic peak/, result)
    assert_match(/Calm waters/, result)
  end

  test "auto_gallery groups consecutive images" do
    content = MarkdownFixture::CONSECUTIVE_IMAGES
    result = render(content)

    assert_match(/<div class="gallery"/, result)
    assert_match(/photo1\.jpg/, result)
    assert_match(/photo2\.jpg/, result)
    assert_match(/photo3\.jpg/, result)
    # photo4 and photo5 should be in a separate gallery after the text
    assert_match(/photo4\.jpg/, result)
    assert_match(/photo5\.jpg/, result)
  end

  test "auto_gallery breaks on non-image lines" do
    content = MarkdownFixture::CONSECUTIVE_IMAGES
    result = render(content)

    # Should have two separate galleries (two <div class="gallery"> elements)
    gallery_count = result.scan(/<div class="gallery">/).count
    assert_equal 2, gallery_count, "Expected two separate galleries"

    # Photo3 should be in first gallery, Photo4 in second
    assert_match(/photo3\.jpg.*<\/div>\s*<p>Some text between/m, result)
    assert_match(/Some text between.*<div class="gallery">.*photo4\.jpg/m, result)
  end

  test "gallery output has gallery class" do
    content = MarkdownFixture::GALLERY_SIMPLE
    result = render(content)

    assert_match(/class="gallery"/, result)
  end

  test "gallery captions use figcaption" do
    content = MarkdownFixture::GALLERY_WITH_CAPTIONS
    result = render(content)

    assert_match(/<figcaption>The majestic peak<\/figcaption>/, result)
  end

  test "gallery handles single image not as gallery" do
    content = "![Single](single.jpg)"
    result = render(content)

    refute_match(/class="gallery"/, result)
    assert_match(/single\.jpg/, result)
  end

  test "gallery images preserve alt text" do
    content = <<~MARKDOWN
      ```gallery
      ![Mountain Image](mountain.jpg)
      ```
    MARKDOWN

    result = render(content)

    assert_match(/alt="Mountain Image"/, result)
  end

  test "gallery with mixed caption formats" do
    content = <<~MARKDOWN
      ```gallery
      ![With caption](img1.jpg)(*Caption one*)
      ![Without caption](img2.jpg)
      ![Another](img3.jpg)(*Caption three*)
      ```
    MARKDOWN

    result = render(content)

    assert_match(/img1\.jpg/, result)
    assert_match(/img2\.jpg/, result)
    assert_match(/img3\.jpg/, result)
  end

  # =============================================================================
  # Pullquote Card Tests
  # =============================================================================

  test "pullquote center renders card with pullquote classes" do
    content = MarkdownFixture::PULLQUOTE_CENTER
    result = render(content)

    assert_match(/class="card card-pullquote pullquote-center"/, result)
    assert_match(/The only way to do great work/, result)
  end

  test "pullquote left renders floated aside" do
    content = MarkdownFixture::PULLQUOTE_LEFT
    result = render(content)

    assert_match(/pullquote-left/, result)
    assert_match(/Float this to the left/, result)
  end

  test "pullquote right renders floated aside" do
    content = MarkdownFixture::PULLQUOTE_RIGHT
    result = render(content)

    assert_match(/pullquote-right/, result)
    assert_match(/Float this to the right/, result)
  end

  test "pullquote with attribution renders cite" do
    content = MarkdownFixture::PULLQUOTE_CENTER
    result = render(content)

    assert_match(/<cite>/, result)
    assert_match(/Steve Jobs/, result)
  end

  test "pullquote without attribution no cite" do
    content = <<~MARKDOWN
      ```card
      type: pullquote
      text: "Quote without attribution"
      position: center
      ```
    MARKDOWN

    result = render(content)

    assert_match(/Quote without attribution/, result)
    refute_match(/<cite>/, result)
  end

  test "pullquote default position is center" do
    content = <<~MARKDOWN
      ```card
      type: pullquote
      text: "No position specified"
      ```
    MARKDOWN

    result = render(content)

    assert_match(/pullquote-center/, result)
  end

  test "pullquote card classes include card and card-pullquote" do
    content = MarkdownFixture::PULLQUOTE_CENTER
    result = render(content)

    assert_match(/class=".*card.*"/, result)
    assert_match(/card-pullquote/, result)
  end

  # =============================================================================
  # Aside Card Tests
  # =============================================================================

  test "aside renders card with aside classes" do
    content = MarkdownFixture::ASIDE_SIMPLE
    result = render(content)

    assert_match(/class="card card-aside"/, result)
    assert_match(/This is an aside/, result)
  end

  test "aside with text only" do
    content = <<~MARKDOWN
      ```card
      type: aside
      text: "Simple aside text"
      ```
    MARKDOWN

    result = render(content)

    assert_match(/Simple aside text/, result)
  end

  test "aside with link inline" do
    content = <<~MARKDOWN
      ```card
      type: aside
      text: "Learn more"
      link: /related
      ```
    MARKDOWN

    result = render(content)

    assert_match(/href="\/related"/, result)
  end

  test "aside with link and link_text" do
    content = MarkdownFixture::ASIDE_WITH_LINK
    result = render(content)

    assert_match(/href="\/related-page"/, result)
    assert_match(/Read more/, result)
  end

  test "aside with image" do
    content = MarkdownFixture::ASIDE_WITH_IMAGE
    result = render(content)

    assert_match(/class="aside-image"/, result)
    assert_match(/src="\/media\/images\/sidebar\.jpg"/, result)
  end

  test "aside uses default link text when link provided without link_text" do
    content = <<~MARKDOWN
      ```card
      type: aside
      text: "Just text"
      link: /some-page
      ```
    MARKDOWN

    result = render(content)

    # Arrow is added when link is provided but link_text is not
    assert_match(/→/, result)
    assert_match(/class="aside-link-inline"/, result)
  end

  # =============================================================================
  # Post Link Card Tests
  # =============================================================================

  test "post_link small style" do
    post = create(:post, metadata: {
      "title" => "Hello World",
      "status" => "published",
      "date" => "2024-01-01",
      "url_name" => "hello-world"
    })

    content = <<~MARKDOWN
      ```card
      type: post-link
      post: hello-world
      style: small
      ```
    MARKDOWN

    result = render(content)

    assert_match(/post-link-small/, result)
    assert_match(/Hello World/, result)
  end

  test "post_link large style" do
    post = create(:post, metadata: {
      "title" => "Hello World",
      "status" => "published",
      "date" => "2024-01-01",
      "url_name" => "hello-world"
    })

    content = <<~MARKDOWN
      ```card
      type: post-link
      post: hello-world
      style: large
      ```
    MARKDOWN

    result = render(content)

    assert_match(/post-link-large/, result)
  end

  test "post_link not found shows error in preview" do
    content = <<~MARKDOWN
      ```card
      type: post-link
      post: nonexistent-post
      style: small
      ```
    MARKDOWN

    # Error only shows in preview mode
    result = render(content, preview: true)

    assert_match(/Content not found: nonexistent-post/, result)
  end

  test "post_link renders link href" do
    post = create(:post, metadata: {
      "title" => "Test Post",
      "status" => "published",
      "date" => "2024-01-01",
      "url_name" => "test-post"
    })

    content = <<~MARKDOWN
      ```card
      type: post-link
      post: test-post
      style: small
      ```
    MARKDOWN

    result = render(content)

    assert_match(/href="\/posts\/test-post"/, result)
  end

  test "post_link override title" do
    post = create(:post, metadata: {
      "title" => "Original Title",
      "status" => "published",
      "date" => "2024-01-01",
      "url_name" => "test-post"
    })

    content = <<~MARKDOWN
      ```card
      type: post-link
      post: test-post
      title: Custom Title
      ```
    MARKDOWN

    result = render(content)

    assert_match(/Custom Title/, result)
    refute_match(/Original Title/, result)
  end

  # =============================================================================
  # Inline Collection Tests
  # =============================================================================

  test "collection renders heading" do
    content = <<~MARKDOWN
      ```collection
      heading: Latest Posts
      ```
    MARKDOWN

    result = render(content)

    assert_match(/Latest Posts/, result)
    assert_match(/class="collection list"/, result)
  end

  test "collection with list template" do
    post = create(:post, metadata: {
      "title" => "Test Post",
      "status" => "published",
      "date" => "2024-01-01"
    })

    content = <<~MARKDOWN
      ```collection
      heading: Posts
      template: list
      limit: 1
      ```
    MARKDOWN

    result = render(content)

    assert_match(/Test Post/, result)
  end

  test "collection with compact template" do
    post = create(:post, metadata: {
      "title" => "Compact Post",
      "status" => "published",
      "date" => "2024-01-01"
    })

    content = <<~MARKDOWN
      ```collection
      heading: Recent
      template: compact
      limit: 1
      ```
    MARKDOWN

    result = render(content)

    assert_match(/Compact Post/, result)
  end

  test "collection with links template" do
    post = create(:post, metadata: {
      "title" => "Links Post",
      "status" => "published",
      "date" => "2024-01-01"
    })

    content = <<~MARKDOWN
      ```collection
      heading: Quick Links
      template: links
      limit: 1
      ```
    MARKDOWN

    result = render(content)

    assert_match(/Links Post/, result)
  end

  test "a content id colliding with a reserved mount (snipcart) is namespaced, not dropped" do
    # Body heading: keeps an anchor id, just not the reserved one.
    html = render("## Snipcart")
    refute_match(/id="snipcart"/, html, "must not claim Snipcart's #snipcart cart mount id")
    assert_match(/id="snipcart-section"/, html, "heading stays anchorable under a namespaced id")

    # Collection item title (same auto_id path) — id kept, reserved word dodged.
    create(:post, metadata: {
      "title" => "Snipcart",
      "status" => "published",
      "date" => "2024-01-01",
      "tags" => [ "collide-check" ]
    })

    %w[links list full].each do |template|
      result = render(<<~MARKDOWN)
        ```collection
        template: #{template}
        tags: collide-check
        ```
      MARKDOWN

      assert_match(/class="item-title"/, result, "#{template}: .item-title hook present")
      assert_match(/Snipcart/, result, "#{template}: title still rendered")
      # Whatever the parser slugs the title to, the output must never carry the
      # bare reserved id that Snipcart's cart mount claims.
      refute_match(/id="snipcart"/, result, "#{template}: reserved mount id dodged")
    end
  end

  test "ordinary heading ids are unaffected by the reserved-mount guard" do
    assert_match(/id="getting-started"/, render("## Getting Started"))
  end

  test "collection respects limit" do
    3.times do |i|
      create(:post, metadata: {
        "title" => "Post #{i}",
        "status" => "published",
        "date" => "2024-01-0#{i+1}"
      })
    end

    content = <<~MARKDOWN
      ```collection
      heading: Limited
      limit: 2
      ```
    MARKDOWN

    result = render(content)

    # Collections are ordered by date descending (newest first)
    # Post 2 (Jan 03) and Post 1 (Jan 02) should appear, Post 0 (Jan 01) should not
    assert_match(/Post 2/, result)
    assert_match(/Post 1/, result)
    refute_match(/Post 0/, result)
  end

  test "collection filters by tags" do
    create(:post, metadata: {
      "title" => "Ruby Post",
      "status" => "published",
      "date" => "2024-01-01",
      "tags" => [ "ruby" ]
    })
    create(:post, metadata: {
      "title" => "Python Post",
      "status" => "published",
      "date" => "2024-01-02",
      "tags" => [ "python" ]
    })

    content = <<~MARKDOWN
      ```collection
      heading: Ruby Only
      tags: ruby
      ```
    MARKDOWN

    result = render(content)

    assert_match(/Ruby Post/, result)
    refute_match(/Python Post/, result)
  end

  test "collection filters by post_type" do
    create(:post, metadata: {
      "title" => "Article",
      "status" => "published",
      "date" => "2024-01-01",
      "post_type" => "article"
    })
    create(:post, metadata: {
      "title" => "Music",
      "status" => "published",
      "date" => "2024-01-02",
      "post_type" => "music"
    })

    content = <<~MARKDOWN
      ```collection
      heading: Articles
      post_type: article
      ```
    MARKDOWN

    result = render(content)

    assert_match(/Article/, result)
    refute_match(/Music/, result)
  end

  test "collection orders by date" do
    create(:post, metadata: {
      "title" => "Older",
      "status" => "published",
      "date" => "2024-01-01"
    })
    create(:post, metadata: {
      "title" => "Newer",
      "status" => "published",
      "date" => "2024-12-31"
    })

    content = <<~MARKDOWN
      ```collection
      heading: By Date
      order: date
      ```
    MARKDOWN

    result = render(content)

    newer_pos = result.index("Newer")
    older_pos = result.index("Older")
    assert newer_pos < older_pos, "Newer should appear before Older"
  end

  test "collection orders by title" do
    create(:post, metadata: {
      "title" => "Zebra Post",
      "status" => "published",
      "date" => "2024-01-01"
    })
    create(:post, metadata: {
      "title" => "Apple Post",
      "status" => "published",
      "date" => "2024-01-02"
    })

    content = <<~MARKDOWN
      ```collection
      heading: A-Z
      order: title
      ```
    MARKDOWN

    result = render(content)

    apple_pos = result.index("Apple Post")
    zebra_pos = result.index("Zebra Post")
    assert apple_pos < zebra_pos, "Apple should appear before Zebra"
  end

  test "collection show_more link" do
    # Create posts to have something to show
    3.times do |i|
      create(:post, metadata: {
        "title" => "Post #{i}",
        "status" => "published",
        "date" => "2024-01-0#{i+1}"
      })
    end

    content = <<~MARKDOWN
      ```collection
      heading: Featured
      limit: 1
      show_more: true
      show_more_text: "View all articles"
      ```
    MARKDOWN

    result = render(content)

    assert_match(/View all articles/, result)
  end

  # =============================================================================
  # Collection Grid Tests
  # =============================================================================

  test "consecutive collections grouped" do
    post1 = create(:post, metadata: { "title" => "Post 1", "status" => "published", "date" => "2024-01-01" })
    post2 = create(:post, metadata: { "title" => "Post 2", "status" => "published", "date" => "2024-01-02" })
    post3 = create(:post, metadata: { "title" => "Post 3", "status" => "published", "date" => "2024-01-03" })

    content = <<~MARKDOWN
      ```collection
      heading: First
      limit: 1
      ```

      ```collection
      heading: Second
      limit: 1
      ```
    MARKDOWN

    result = render(content)

    assert_match(/First/, result)
    assert_match(/Second/, result)
  end

  # =============================================================================
  # Edge Cases
  # =============================================================================

  test "handles empty card blocks" do
    content = <<~MARKDOWN
      ```card
      ```
    MARKDOWN

    result = render(content)

    assert result.present?
  end

  test "handles empty collection blocks" do
    content = <<~MARKDOWN
      ```collection
      ```
    MARKDOWN

    result = render(content)

    assert result.present?
  end

  test "handles empty gallery blocks" do
    content = <<~MARKDOWN
      ```gallery
      ```
    MARKDOWN

    # Empty galleries return empty or whitespace-only string in production
    result = render(content)
    assert result.blank?, "Expected empty gallery to return blank result, got: #{result.inspect}"

    # Empty galleries return HTML comment in preview mode
    result_preview = render(content, preview: true)
    assert_match(/<!-- Empty gallery -->/, result_preview)
  end

  test "unknown card type returns empty in production" do
    content = <<~MARKDOWN
      ```card
      type: unknown
      text: "Something"
      ```
    MARKDOWN

    result = render(content)

    assert result.blank?
  end

  # =============================================================================
  # Media embed tests (Obsidian-style `![](file.mp3|mp4)`)
  # =============================================================================

  test "audio file embed renders a native audio player" do
    result = render("![Episode 1](/media/audio/audio-abc.mp3)")

    assert_match(%r{<audio[^>]*controls}, result)
    assert_match(%r{src="/media/audio/audio-abc\.mp3"}, result)
    assert_match(/aria-label="Episode 1"/, result)
    refute_match(/<img/, result)
  end

  test "video file embed renders a native video player" do
    result = render("![Clip](/media/video/clip.mp4)")

    assert_match(%r{<video[^>]*controls}, result)
    assert_match(%r{src="/media/video/clip\.mp4"}, result)
    refute_match(/<img/, result)
  end

  test "audio embed without alt omits aria-label but still plays" do
    result = render("![](/media/audio/audio-xyz.m4a)")

    assert_match(%r{<audio[^>]*controls}, result)
    refute_match(/aria-label=/, result)
  end

  test "image embeds are unaffected by media embed handling" do
    result = render("![A photo](/media/images/pic.jpg)")

    refute_match(/<audio/, result)
    refute_match(/<video/, result)
  end

  # =============================================================================
  # Search triggers (```search block + collection search: true)
  # =============================================================================

  test "search block renders a scoped search trigger with sources and tags" do
    result = render("```search\nscope: documentation/products\ntags: ruby, -news\n```")

    assert_match(/class="site-search-trigger"/, result)
    assert_match(/data-search-trigger-scope-value=/, result)
    assert_match(/documentation/, result)
    assert_match(/products/, result)
    assert_match(/tagsInclude/, result)
    assert_match(/tagsExclude/, result)
  end

  test "search block treats a non-directory token as a post type" do
    result = render("```search\nscope: podcast\n```")

    assert_match(/data-search-trigger-scope-value=/, result)
    assert_match(/postTypes/, result)
    assert_match(/podcast/, result)
  end

  test "collection with search true renders the trigger inside a collection header" do
    result = render("```collection\nsource: documentation\nsearch: true\n```")

    assert_match(%r{<div class="collection-header">.*site-search-trigger}m, result)
    assert_match(/documentation/, result)
  end

  test "collection without search does not render a trigger" do
    result = render("```collection\nsource: documentation\n```")

    refute_match(/site-search-trigger/, result)
  end

  test "basic markdown still processed" do
    content = <<~MARKDOWN
      # Header

      Paragraph with **bold** text.
    MARKDOWN

    result = render(content)

    # Headers get auto-generated IDs
    assert_match(/<h1 id="header">Header<\/h1>/, result)
    assert_match(/<strong>bold<\/strong>/, result)
  end

  # =============================================================================
  # Roe-anji for / type selector (button + form)
  # =============================================================================

  def kind(config, **opts)
    TestModel.new("").send(:roeanji_kind, config, **opts)
  end

  def conflict_warning(config)
    TestModel.new("").send(:roeanji_kind_conflict_warning, config)
  end

  def in_dev_env
    original = Rails.env.to_s
    Rails.env = "development"
    yield
  ensure
    Rails.env = original
  end

  test "roeanji_kind reads `for`" do
    assert_equal "share", kind({ "for" => "share" })
  end

  test "roeanji_kind reads `type` as an alias" do
    assert_equal "signup", kind({ "type" => "signup" })
  end

  test "roeanji_kind: `for` wins when both are present" do
    assert_equal "share", kind({ "for" => "share", "type" => "product" })
  end

  test "roeanji_kind falls back to the default only when neither is set" do
    assert_equal "product", kind({}, default: "product")
    assert_nil kind({})
  end

  test "conflict warning is empty unless for and type disagree" do
    assert_equal "", conflict_warning({ "for" => "share" })
    assert_equal "", conflict_warning({ "type" => "share" })
    assert_equal "", conflict_warning({ "for" => "share", "type" => "share" })
    assert_equal "", conflict_warning({})
  end

  test "conflict warning fires (in dev) when for and type disagree" do
    in_dev_env do
      html = conflict_warning({ "for" => "share", "type" => "product" })
      assert_includes html, "Conflicting selector"
      assert_includes html, "for` wins"
    end
  end

  test "an unknown non-product button dev-warns in dev, silent otherwise" do
    button = { kind: "mystery", config: {} }
    assert_equal "", TestModel.new("").send(:render_action_button, button, {}), "silent outside dev"

    in_dev_env do
      html = TestModel.new("").send(:render_action_button, button, {})
      assert_includes html, "Unknown button type"
      assert_includes html, "mystery"
    end
  end

  # ---- share button ----------------------------------------------------------

  test "render_share_button emits a Share trigger + copy/email menu" do
    html = TestModel.new("").send(:render_share_button, {}, {})
    assert_includes html, 'data-controller="share"'
    assert_includes html, 'data-share-target="trigger"'
    assert_includes html, 'data-action="share#toggle"'
    assert_includes html, 'data-share-target="menu"'
    assert_includes html, 'data-action="share#copy"'
    assert_includes html, 'href="mailto:"'
    assert_includes html, ">Share</button>"   # default trigger label
    assert_includes html, ">Copy link</button>"
  end

  test "share button honours label + url/title/text config" do
    html = TestModel.new("").send(:render_share_button,
      { "label" => "Send it", "url" => "/x", "title" => "T", "text" => "msg" }, {})
    assert_includes html, ">Send it</button>"
    assert_includes html, 'data-share-url-value="/x"'
    assert_includes html, 'data-share-title-value="T"'
    assert_includes html, 'data-share-text-value="msg"'
  end

  test "`for: share` routes through the pipeline to the share button" do
    html = render("```button\nfor: share\n```")
    assert_includes html, 'data-controller="share"'
    assert_includes html, "share#copy"
  end

  test "`type: share` is an alias for `for: share`" do
    html = render("```button\ntype: share\n```")
    assert_includes html, 'data-controller="share"'
  end

  # ---- members (subscribe) button --------------------------------------------

  def with_members_enabled(enabled = true)
    sc = SiteFeature.singleton_class
    sc.send(:alias_method, :__orig_members_enabled?, :members_enabled?)
    sc.send(:define_method, :members_enabled?) { enabled }
    yield
  ensure
    sc.send(:alias_method, :members_enabled?, :__orig_members_enabled?)
    sc.send(:remove_method, :__orig_members_enabled?)
  end

  test "members button links to /sign-up with a Subscribe label" do
    with_members_enabled do
      html = TestModel.new("").send(:render_members_button, {}, {})
      assert_includes html, '<a class="btn-primary" href="/sign-up">Subscribe</a>'
    end
  end

  test "members button honours label / url / style" do
    with_members_enabled do
      html = TestModel.new("").send(:render_members_button,
        { "label" => "Join", "url" => "/upgrade", "style" => "small" }, {})
      assert_includes html, ">Join</a>"
      assert_includes html, 'href="/upgrade"'
      assert_includes html, 'class="btn-primary members-small"'
    end
  end

  test "members button dev-warns in dev, silent otherwise, when members are off" do
    with_members_enabled(false) do
      assert_equal "", TestModel.new("").send(:render_members_button, {}, {}), "silent outside dev"
      in_dev_env do
        html = TestModel.new("").send(:render_members_button, {}, {})
        assert_includes html, "Subscribe button unavailable"
      end
    end
  end

  test "`for: subscribe` (and `type: subscribe`) route to the members button" do
    with_members_enabled do
      assert_includes render("```button\nfor: subscribe\n```"), 'href="/sign-up"'
      assert_includes render("```button\ntype: subscribe\n```"), 'href="/sign-up"'
    end
  end

  test "share button adds NO container class by default + omits empty values" do
    html = TestModel.new("").send(:render_share_button, {}, {})
    # Container closes right after data-controller — no class, no blank values.
    assert_includes html, '<div data-controller="share">'
    refute_includes html, 'data-share-url-value'
  end

  test "share menu uses the reusable .button-menu hook" do
    html = TestModel.new("").send(:render_share_button, {}, {})
    assert_includes html, '<div class="button-menu" data-share-target="menu">'
  end

  test "share button `style:` adds sanitised modifier classes only" do
    html = TestModel.new("").send(:render_share_button, { "style" => "small center" }, {})
    assert_includes html, '<div class="share-small share-center" data-controller="share"'
  end

  test "share button `style:` strips unsafe characters" do
    html = TestModel.new("").send(:render_share_button, { "style" => "sm<all>" }, {})
    assert_includes html, 'class="share-small"'
  end
end
