require "test_helper"
require "ostruct"

class NewsletterRendererTest < ActiveSupport::TestCase
  def setup
    super
    
    @public_post = create(:post,
      metadata: {
        "title" => "Test Post for Newsletter",
        "status" => "published",
        "date" => "2024-01-01",
        "author" => "Test Author"
      },
      content: "# Hello World\n\nThis is test content for the newsletter.\n\n- Item 1\n- Item 2"
    )
    
    @member = create(:member, 
      name: "Test Member",
      email: "member@example.com"
    )
  end

  # ============================================================================
  # Basic Rendering
  # ============================================================================

  test "renders post content to HTML" do
    renderer = NewsletterRenderer.new(@public_post)
    html = renderer.render
    
    assert_includes html, "Hello World"
    assert_includes html, "This is test content for the newsletter"
    assert_includes html, "<ul>"
    assert_includes html, "<li>Item 1</li>"
  end

  test "preview returns HTML without CSS inlining" do
    renderer = NewsletterRenderer.new(@public_post)
    html = renderer.preview
    
    assert_includes html, "Hello World"
    assert_includes html, "<h1>"
  end

  test "render wraps content in email template" do
    renderer = NewsletterRenderer.new(@public_post)
    html = renderer.render
    
    # Should have email structure
    assert_includes html, "<!DOCTYPE"
    assert_includes html, "<html"
    assert_includes html, "<body"
  end

  # ============================================================================
  # Post Attributes
  # ============================================================================

  test "includes post title in email" do
    renderer = NewsletterRenderer.new(@public_post)
    html = renderer.render
    
    assert_includes html, "Test Post for Newsletter"
  end

  test "includes post author when available" do
    renderer = NewsletterRenderer.new(@public_post)
    html = renderer.render
    
    assert_includes html, "Test Author"
  end

  test "handles posts without author" do
    post_without_author = create(:post,
      metadata: {
        "title" => "No Author Post",
        "status" => "published",
        "date" => "2024-01-02"
      },
      content: "# Content"
    )
    
    renderer = NewsletterRenderer.new(post_without_author)
    html = renderer.render
    
    assert_includes html, "No Author Post"
  end

  # ============================================================================
  # Content Processing
  # ============================================================================

  test "converts markdown to HTML" do
    post_with_markdown = create(:post,
      metadata: {
        "title" => "Markdown Post",
        "status" => "published",
        "date" => "2024-01-03"
      },
      content: "# Heading\n\n**Bold text** and *italic text*"
    )
    
    renderer = NewsletterRenderer.new(post_with_markdown)
    html = renderer.render
    
    assert_includes html, "<strong>Bold text</strong>"
    assert_includes html, "<em>italic text</em>"
  end

  test "converts relative URLs to absolute" do
    SiteConfig.stubs(:current).returns(
      OpenStruct.new(config: { "url" => "https://example.com" })
    )
    
    post_with_links = create(:post,
      metadata: {
        "title" => "Link Post",
        "status" => "published",
        "date" => "2024-01-04"
      },
      content: "[Link](/posts/test) and ![Image](/media/test.jpg)"
    )
    
    renderer = NewsletterRenderer.new(post_with_links)
    html = renderer.render
    
    assert_includes html, "https://example.com/posts/test"
    assert_includes html, "https://example.com/media/test.jpg"
  end

  test "uses localhost fallback when site URL not configured" do
    SiteConfig.stubs(:current).returns(nil)
    
    renderer = NewsletterRenderer.new(@public_post)
    html = renderer.render
    
    # Should still render successfully
    assert_includes html, "Hello World"
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  test "handles posts with code blocks" do
    post_with_code = create(:post,
      metadata: {
        "title" => "Code Post",
        "status" => "published",
        "date" => "2024-01-05"
      },
      content: "```ruby\nputs 'Hello'\n```"
    )
    
    renderer = NewsletterRenderer.new(post_with_code)
    html = renderer.render
    
    assert_includes html, "puts"
    assert_includes html, "Hello"
  end

  test "handles very long content" do
    long_content = "Word " * 1000
    post_with_long_content = create(:post,
      metadata: {
        "title" => "Long Post",
        "status" => "published",
        "date" => "2024-01-06"
      },
      content: long_content
    )
    
    renderer = NewsletterRenderer.new(post_with_long_content)
    html = renderer.render
    
    # Should render without errors
    assert html.length > 1000
  end

  test "handles special characters in content" do
    post_with_special = create(:post,
      metadata: {
        "title" => "Special Post",
        "status" => "published",
        "date" => "2024-01-07"
      },
      content: "Special chars: ñ, é, ü, 日本語, 🎉, <script>"
    )
    
    renderer = NewsletterRenderer.new(post_with_special)
    html = renderer.render
    
    assert_includes html, "ñ"
    assert_includes html, "日本語"
  end

  test "handles empty content gracefully" do
    post_with_empty = create(:post,
      metadata: {
        "title" => "Empty Post",
        "status" => "published",
        "date" => "2024-01-08"
      },
      content: ""
    )
    
    renderer = NewsletterRenderer.new(post_with_empty)
    html = renderer.render
    
    # Should render template even with empty content
    assert_includes html, "<!DOCTYPE"
    assert_includes html, "Empty Post"
  end

  # ============================================================================
  # Initialization
  # ============================================================================

  test "initializes with post only" do
    renderer = NewsletterRenderer.new(@public_post)
    assert_equal @public_post, renderer.post
    assert_nil renderer.member
  end

  test "initializes with post and member" do
    renderer = NewsletterRenderer.new(@public_post, @member)
    assert_equal @public_post, renderer.post
    assert_equal @member, renderer.member
  end
end
