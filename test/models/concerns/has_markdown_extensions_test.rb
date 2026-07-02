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
end
