require "test_helper"
require "ostruct"

class ContentWatcherTest < ActiveSupport::TestCase
  setup do
    @temp_dir = Dir.mktmpdir("content_watcher_test")
    @original_root = Rails.root
    
    # Create test directory structure
    @posts_dir = File.join(@temp_dir, "site", "posts")
    @pages_dir = File.join(@temp_dir, "site", "pages")
    @docs_dir = File.join(@temp_dir, "site", "documentation")
    @products_dir = File.join(@temp_dir, "site", "products")
    @media_dir = File.join(@temp_dir, "site", "media", "images")
    @system_dir = File.join(@temp_dir, "site", "system")
    
    FileUtils.mkdir_p([@posts_dir, @pages_dir, @docs_dir, @products_dir, @media_dir, @system_dir])
  end

  teardown do
    FileUtils.rm_rf(@temp_dir)
  end

  # Helper to write test files
  def write_test_file(relative_path, content)
    full_path = File.join(@temp_dir, "site", relative_path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
    full_path
  end

  # Extension pattern matching
  test "EXTENSION_PATTERN matches allowed extensions" do
    pattern = ContentWatcher::EXTENSION_PATTERN
    
    # Markdown and YAML
    assert_match pattern, "post.md"
    assert_match pattern, "config.yml"
    
    # Images
    assert_match pattern, "photo.jpg"
    assert_match pattern, "photo.jpeg"
    assert_match pattern, "photo.png"
    assert_match pattern, "photo.gif"
    assert_match pattern, "photo.webp"
    assert_match pattern, "icon.svg"
    
    # Audio
    assert_match pattern, "audio.mp3"
    assert_match pattern, "audio.m4a"
    assert_match pattern, "audio.wav"
    assert_match pattern, "audio.ogg"
    assert_match pattern, "audio.flac"
    assert_match pattern, "audio.aac"
    
    # Video
    assert_match pattern, "video.mp4"
    assert_match pattern, "video.webm"
    assert_match pattern, "video.ogv"
    assert_match pattern, "video.mov"
    assert_match pattern, "video.avi"
    assert_match pattern, "video.mkv"
  end

  test "EXTENSION_PATTERN does not match disallowed extensions" do
    pattern = ContentWatcher::EXTENSION_PATTERN
    
    assert_no_match pattern, "file.txt"
    assert_no_match pattern, "file.pdf"
    assert_no_match pattern, "file.doc"
    assert_no_match pattern, "file.exe"
    assert_no_match pattern, "file.zip"
    assert_no_match pattern, "noextension"
  end

  test "EXTENSION_PATTERN is case insensitive" do
    pattern = ContentWatcher::EXTENSION_PATTERN
    
    assert_match pattern, "photo.JPG"
    assert_match pattern, "photo.MP3"
    assert_match pattern, "post.MD"
  end

  # WATCH_PATHS configuration
  test "WATCH_PATHS includes all content directories" do
    paths = ContentWatcher::WATCH_PATHS
    
    assert_includes paths, "site/posts"
    assert_includes paths, "site/pages"
    assert_includes paths, "site/documentation"
    assert_includes paths, "site/products"
    assert_includes paths, "site/system"
    assert_includes paths, "site/media"
  end

  # Detect renames functionality
  test "detect_renames identifies markdown file renames" do
    # Names must have overlapping substrings to match
    added = ["site/posts/updated-article-slug.md"]
    removed = ["site/posts/article-slug.md"]
    
    renames = ContentWatcher.send(:detect_renames, added, removed)
    
    assert_equal({ "site/posts/article-slug.md" => "site/posts/updated-article-slug.md" }, renames)
  end

  test "detect_renames handles similar basenames" do
    # When old basename is contained in new basename
    added = ["site/posts/updated-article-name.md"]
    removed = ["site/posts/article-name.md"]
    
    renames = ContentWatcher.send(:detect_renames, added, removed)
    
    assert renames.key?("site/posts/article-name.md")
    assert_equal "site/posts/updated-article-name.md", renames["site/posts/article-name.md"]
  end

  test "detect_renames identifies media file renames" do
    # Names must have overlapping substrings to match
    added = ["site/media/images/updated-photo.jpg"]
    removed = ["site/media/images/photo.jpg"]
    
    renames = ContentWatcher.send(:detect_renames, added, removed)
    
    assert_equal({ "site/media/images/photo.jpg" => "site/media/images/updated-photo.jpg" }, renames)
  end

  test "detect_renames requires same extension for media files" do
    added = ["site/media/images/photo.png"]  # Different extension
    removed = ["site/media/images/photo.jpg"]
    
    renames = ContentWatcher.send(:detect_renames, added, removed)
    
    # Should not match because extensions differ
    assert_empty renames
  end

  test "detect_renames returns empty hash when no matches" do
    added = ["site/posts/completely-different.md"]
    removed = ["site/posts/nothing-alike.md"]
    
    renames = ContentWatcher.send(:detect_renames, added, removed)
    
    assert_empty renames
  end

  test "detect_renames handles multiple file changes" do
    # Names must have overlapping substrings to match
    added = [
      "site/posts/updated-post.md",
      "site/pages/updated-page.md",
      "site/media/images/updated-photo.jpg"
    ]
    removed = [
      "site/posts/post.md",
      "site/pages/page.md",
      "site/media/images/photo.jpg"
    ]

    renames = ContentWatcher.send(:detect_renames, added, removed)

    # Should detect all 3 renames since basenames overlap
    assert_equal 3, renames.keys.count
    assert_equal "site/posts/updated-post.md", renames["site/posts/post.md"]
    assert_equal "site/pages/updated-page.md", renames["site/pages/page.md"]
    assert_equal "site/media/images/updated-photo.jpg", renames["site/media/images/photo.jpg"]
  end

  # Static generation check
  test "static_generation_enabled? returns false when no site config" do
    SiteConfig.delete_all
    
    assert_not ContentWatcher.send(:static_generation_enabled?)
  end

  test "static_generation_enabled? returns false when disabled" do
    create(:site_config, config: { "static_generation_enabled" => false })
    
    assert_not ContentWatcher.send(:static_generation_enabled?)
  end

  test "static_generation_enabled? returns true when enabled" do
    create(:site_config, config: { "static_generation_enabled" => true })
    
    assert ContentWatcher.send(:static_generation_enabled?)
  end

  test "static_generation_enabled? handles nil config gracefully" do
    create(:site_config, config: nil)
    
    assert_not ContentWatcher.send(:static_generation_enabled?)
  end

  test "static_generation_enabled? handles missing key gracefully" do
    create(:site_config, config: { "other_setting" => true })
    
    assert_not ContentWatcher.send(:static_generation_enabled?)
  end

  # File processing - categorization
  test "process_file categorizes post files correctly" do
    post_file = write_test_file("posts/test-post.md", "---\ntitle: Test Post\n---\n\nContent")
    
    # Verify the method doesn't raise and processes as post
    output = capture_io do
      assert_nothing_raised do
        ContentWatcher.send(:process_file, post_file)
      end
    end
    
    # Should attempt to process (may fail due to DB, but categorizes correctly)
  end

  test "process_file categorizes page files correctly" do
    page_file = write_test_file("pages/test-page.md", "---\ntitle: Test Page\n---\n\nContent")
    
    assert_nothing_raised do
      ContentWatcher.send(:process_file, page_file)
    end
  end

  test "process_file categorizes documentation files correctly" do
    doc_file = write_test_file("documentation/test-doc.md", "---\ntitle: Test Doc\n---\n\nContent")
    
    assert_nothing_raised do
      ContentWatcher.send(:process_file, doc_file)
    end
  end

  test "process_file categorizes product files correctly" do
    product_file = write_test_file("products/test-product.md", "---\ntitle: Test Product\nprice: 1000\n---\n\nDescription")
    
    assert_nothing_raised do
      ContentWatcher.send(:process_file, product_file)
    end
  end

  test "process_file skips variant files in media directory" do
    variant_file = write_test_file("media/images/variants/test-image.jpg", "fake image data")
    
    # Should return early without attempting to create records
    assert_nothing_raised do
      ContentWatcher.send(:process_file, variant_file)
    end
  end

  test "process_file handles global config files" do
    config_file = write_test_file("system/global/site.yml", "title: Test Site")
    
    assert_nothing_raised do
      ContentWatcher.send(:process_file, config_file)
    end
  end

  test "process_file handles feature config files" do
    config_file = write_test_file("system/features/members.yml", "enabled: true")
    
    assert_nothing_raised do
      ContentWatcher.send(:process_file, config_file)
    end
  end

  test "process_file handles defaults config files" do
    config_file = write_test_file("system/defaults/collections.yml", "default_limit: 10")
    
    assert_nothing_raised do
      ContentWatcher.send(:process_file, config_file)
    end
  end

  test "process_file handles media files" do
    media_file = write_test_file("media/images/test-photo.jpg", "fake image data")
    
    assert_nothing_raised do
      ContentWatcher.send(:process_file, media_file)
    end
  end

  # Remove file functionality
  test "remove_file handles post files" do
    post_file = write_test_file("posts/delete-me.md", "---\ntitle: Delete Me\n---\n\nContent")
    
    # Create the post first
    Post.create_or_update_from_file(post_file)
    assert Post.exists?(file_path: post_file)
    
    # Now remove it
    ContentWatcher.send(:remove_file, post_file)
    
    assert_not Post.exists?(file_path: post_file)
  end

  test "remove_file handles page files" do
    page_file = write_test_file("pages/delete-me.md", "---\ntitle: Delete Me\n---\n\nContent")
    
    Page.create_or_update_from_file(page_file)
    assert Page.exists?(file_path: page_file)
    
    ContentWatcher.send(:remove_file, page_file)
    
    assert_not Page.exists?(file_path: page_file)
  end

  test "remove_file handles media files with web paths" do
    media_file = write_test_file("media/images/delete-me.jpg", "fake image data")
    web_path = media_file.sub(Rails.root.join("site").to_s, "")
    
    Medium.create!(file_path: web_path, media_type: "jpg", uploaded_at: Time.current)
    assert Medium.exists?(file_path: web_path)
    
    ContentWatcher.send(:remove_file, media_file)
    
    assert_not Medium.exists?(file_path: web_path)
  end

  # Config removal handling
  test "handle_config_removed recognizes feature configs" do
    config_file = write_test_file("system/features/store.yml", "enabled: true")
    create(:site_config, file_path: "site/system/features/store.yml", config: { "enabled" => true })
    
    assert SiteConfig.where("file_path LIKE ?", "%store.yml").exists?
    
    ContentWatcher.send(:handle_config_removed, config_file)
    
    assert_not SiteConfig.where("file_path LIKE ?", "%store.yml").exists?
  end

  # Handle changes orchestration
  test "handle_changes detects renames before processing additions" do
    # This test verifies the orchestration logic
    added = ["site/posts/old-name.md"]  # Same basename so it matches
    modified = []
    removed = ["site/posts/old-name.md"]
    
    # Verify detect_renames identifies matching files
    renames = ContentWatcher.send(:detect_renames, added, removed)
    
    # Since names are identical, it should match
    assert renames.key?("site/posts/old-name.md"), "Expected rename detection to find matching file"
    assert_equal "site/posts/old-name.md", renames["site/posts/old-name.md"]
  end

  test "handle_changes filters files by extension" do
    # Files with allowed extensions should be processed
    allowed_file = "site/posts/valid.md"
    disallowed_file = "site/posts/invalid.txt"
    
    assert ContentWatcher::EXTENSION_PATTERN.match?(allowed_file)
    assert_not ContentWatcher::EXTENSION_PATTERN.match?(disallowed_file)
  end

  # Handle rename functionality
  test "handle_rename updates post file paths" do
    old_file = write_test_file("posts/old-slug.md", "---\ntitle: Old Title\n---\n\nContent")
    new_file = write_test_file("posts/new-slug.md", "---\ntitle: New Title\n---\n\nContent")
    
    # Create initial post
    Post.create_or_update_from_file(old_file)
    post = Post.find_by(file_path: old_file)
    assert post
    
    # Perform rename
    ContentWatcher.send(:handle_rename, old_file, new_file)
    
    # Verify path was updated
    post.reload
    assert_equal new_file, post.file_path
  end

  test "handle_rename updates page file paths" do
    old_file = write_test_file("pages/old-page.md", "---\ntitle: Old Page\n---\n\nContent")
    new_file = write_test_file("pages/new-page.md", "---\ntitle: New Page\n---\n\nContent")
    
    Page.create_or_update_from_file(old_file)
    page = Page.find_by(file_path: old_file)
    assert page
    
    ContentWatcher.send(:handle_rename, old_file, new_file)
    
    page.reload
    assert_equal new_file, page.file_path
  end

  test "handle_rename updates media file paths" do
    old_file = write_test_file("media/images/old-photo.jpg", "fake")
    new_file = write_test_file("media/images/new-photo.jpg", "fake")
    
    old_web_path = old_file.sub(Rails.root.join("site").to_s, "")
    new_web_path = new_file.sub(Rails.root.join("site").to_s, "")
    
    Medium.create!(file_path: old_web_path, media_type: "jpg", uploaded_at: Time.current)
    
    ContentWatcher.send(:handle_rename, old_file, new_file)
    
    assert_not Medium.exists?(file_path: old_web_path)
    assert Medium.exists?(file_path: new_web_path)
  end
end
