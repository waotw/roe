require "test_helper"

class StaticGeneratorTest < ActiveSupport::TestCase
  def setup
    @public_test_dir = File.join(Rails.root, "public_test")
    FileUtils.mkdir_p(@public_test_dir)
  end

  def teardown
    FileUtils.rm_rf(@public_test_dir)
    super
  end

  # Helper to create manifest file with given data
  def create_manifest(data)
    manifest_path = File.join(@public_test_dir, ".generation_manifest.json")
    File.write(manifest_path, JSON.generate(data))
  end

  test "manifest created on first run" do
    generator = StaticGenerator.new(output_dir: @public_test_dir)

    # Trigger manifest loading (which returns empty hash when not exists)
    manifest = generator.send(:load_manifest)

    # Should return empty hash, not raise error
    assert_equal({}, manifest)

    # Save manifest should create the file
    generator.send(:save_manifest)

    manifest_path = File.join(@public_test_dir, ".generation_manifest.json")
    assert File.exist?(manifest_path)
  end

  test "manifest has correct structure after save" do
    generator = StaticGenerator.new(output_dir: @public_test_dir)
    generator.send(:save_manifest)

    manifest_path = File.join(@public_test_dir, ".generation_manifest.json")
    manifest = JSON.parse(File.read(manifest_path))

    assert manifest.key?("generated_at")
    assert manifest.key?("posts")
    assert manifest.key?("pages")
    assert manifest.key?("documentation")
    assert manifest.key?("configs")
    assert manifest.key?("layouts")
    assert manifest.key?("assets")
  end

  test "config change detected when config updated" do
    public_dir = @public_test_dir

    manifest = {
      "generated_at" => 1.hour.ago.iso8601,
      "configs" => {
        "site" => 2.hours.ago.iso8601
      }
    }
    create_manifest(manifest)

    generator = StaticGenerator.new(output_dir: public_dir)
    # Load manifest into instance variable
    generator.instance_variable_set(:@manifest, generator.send(:load_manifest))

    # Create a site config that's newer than manifest
    SiteConfig.where(file_path: "site/system/global/site.yml").destroy_all
    site_config = create(:site_config,
      file_path: "site/system/global/site.yml",
      config: { "title" => "Updated" }
    )
    site_config.touch

    assert generator.send(:config_file_changed?, "site")
  end

  test "config not changed when config is older" do
    public_dir = @public_test_dir

    manifest = {
      "generated_at" => 1.hour.ago.iso8601,
      "configs" => {
        "site" => Time.current.iso8601
      }
    }
    create_manifest(manifest)

    generator = StaticGenerator.new(output_dir: public_dir)
    generator.instance_variable_set(:@manifest, generator.send(:load_manifest))

    # Create old config
    SiteConfig.where(file_path: "site/system/global/site.yml").destroy_all
    site_config = create(:site_config,
      file_path: "site/system/global/site.yml",
      config: { "title" => "Old" }
    )
    site_config.update_column(:updated_at, 2.hours.ago)

    assert_not generator.send(:config_file_changed?, "site")
  end

  test "changed_items detects updated content" do
    public_dir = @public_test_dir
    old_time = 2.hours.ago

    post = create(:post, metadata: { "title" => "Test", "status" => "published", "date" => "2024-01-01" })
    post.update_column(:updated_at, Time.current)

    manifest = {
      "generated_at" => old_time.iso8601,
      "posts" => {
        post.id.to_s => {
          "updated_at" => old_time.iso8601,
          "html_file" => "posts/test.html"
        }
      }
    }
    create_manifest(manifest)

    generator = StaticGenerator.new(output_dir: public_dir)
    generator.instance_variable_set(:@manifest, generator.send(:load_manifest))

    changed = generator.send(:changed_items, Post.not_draft, "posts")

    assert_includes changed, post
  end

  test "changed_items excludes unchanged content" do
    public_dir = @public_test_dir
    recent_time = Time.current

    post = create(:post, metadata: { "title" => "Test", "status" => "published", "date" => "2024-01-01" })
    post.update_column(:updated_at, 1.hour.ago)

    manifest = {
      "generated_at" => recent_time.iso8601,
      "posts" => {
        post.id.to_s => {
          "updated_at" => recent_time.iso8601,
          "html_file" => "posts/test.html"
        }
      }
    }
    create_manifest(manifest)

    generator = StaticGenerator.new(output_dir: public_dir)
    generator.instance_variable_set(:@manifest, generator.send(:load_manifest))

    changed = generator.send(:changed_items, Post.not_draft, "posts")

    assert_not_includes changed, post
  end

  test "prepare_output_directory creates output directory" do
    new_output_dir = File.join(@public_test_dir, "new_output")
    generator = StaticGenerator.new(output_dir: new_output_dir)

    assert_not Dir.exist?(new_output_dir)
    generator.send(:prepare_output_directory)
    assert Dir.exist?(new_output_dir)
  end

  test "html_filename_for_type generates correct filenames" do
    generator = StaticGenerator.new(output_dir: @public_test_dir)

    assert_equal "posts/test-post.html", generator.send(:html_filename_for_type, "Post", "test-post")
    assert_equal "about.html", generator.send(:html_filename_for_type, "Page", "about")
    assert_equal "documentation/getting-started.html", generator.send(:html_filename_for_type, "Documentation", "getting-started")
  end

  test "generate_collection_url_path generates correct paths" do
    generator = StaticGenerator.new(output_dir: @public_test_dir)

    # Test with heading
    config = { heading: "Ruby Articles" }
    assert_equal "/collections/ruby-articles", generator.send(:generate_collection_url_path, config)

    # Test with post_type only
    config = { post_type: "article" }
    assert_equal "/collections/type-article", generator.send(:generate_collection_url_path, config)

    # Test with tags only
    config = { tags: "ruby, rails" }
    assert_equal "/collections/ruby,rails", generator.send(:generate_collection_url_path, config)

    # Test default (no filters)
    config = {}
    assert_equal "/collections/all", generator.send(:generate_collection_url_path, config)
  end

  test "layout_checksums returns hash of layout files" do
    # Create a test layout file
    layout_dir = File.join(Rails.root, "site", "layout")
    FileUtils.mkdir_p(layout_dir)
    layout_file = File.join(layout_dir, "navigation.md")
    File.write(layout_file, "# Navigation")

    generator = StaticGenerator.new(output_dir: @public_test_dir)
    checksums = generator.send(:layout_checksums)

    assert checksums.is_a?(Hash)
    assert checksums.key?(layout_file)
    assert checksums[layout_file].is_a?(Integer)
  ensure
    FileUtils.rm_rf(layout_dir)
  end

  test "asset_checksums returns hash of asset directories" do
    # Create test font file
    fonts_dir = File.join(Rails.root, "site", "system", "assets", "fonts")
    FileUtils.mkdir_p(fonts_dir)
    test_font = File.join(fonts_dir, "TestFont.ttf")
    File.write(test_font, "fake font data")

    generator = StaticGenerator.new(output_dir: @public_test_dir)
    checksums = generator.send(:asset_checksums)

    assert checksums.is_a?(Hash)
    assert checksums.key?(:fonts)
    assert checksums[:fonts].is_a?(Hash)
  ensure
    FileUtils.rm_rf(fonts_dir)
  end

  test "layouts_changed? detects new layout files" do
    public_dir = @public_test_dir

    # Empty manifest
    create_manifest({ "generated_at" => Time.current.iso8601, "layouts" => {} })

    # Create a layout file
    layout_dir = File.join(Rails.root, "site", "layout")
    FileUtils.mkdir_p(layout_dir)
    layout_file = File.join(layout_dir, "footer.md")
    File.write(layout_file, "# Footer")

    generator = StaticGenerator.new(output_dir: public_dir)
    generator.instance_variable_set(:@manifest, generator.send(:load_manifest))

    assert generator.send(:layouts_changed?)
  ensure
    FileUtils.rm_rf(layout_dir)
  end

  test "podcast_config_changed? detects podcast config changes" do
    public_dir = @public_test_dir

    create_manifest({
      "generated_at" => 1.hour.ago.iso8601,
      "configs" => { "podcast" => 2.hours.ago.iso8601 }
    })

    # Create podcast config
    podcast_config = create(:site_config,
      file_path: "site/system/features/podcast.yml",
      config: { "enabled" => true }
    )
    podcast_config.touch

    generator = StaticGenerator.new(output_dir: public_dir)
    generator.instance_variable_set(:@manifest, generator.send(:load_manifest))

    assert generator.send(:podcast_config_changed?)
  end

  test "cleanup_deleted_files removes orphaned HTML files" do
    public_dir = @public_test_dir
    FileUtils.mkdir_p(File.join(public_dir, "posts"))

    # Create an HTML file that has no corresponding post
    orphaned_file = File.join(public_dir, "posts", "deleted-post.html")
    File.write(orphaned_file, "<html>Deleted</html>")

    # Create manifest with a deleted post entry
    create_manifest({
      "generated_at" => Time.current.iso8601,
      "posts" => {
        "99999" => {
          "updated_at" => 1.hour.ago.iso8601,
          "html_file" => "posts/deleted-post.html"
        }
      }
    })

    # Create a current post (different from orphaned file)
    current_post = create(:post, metadata: { "title" => "Current", "status" => "published", "date" => "2024-01-01" })

    generator = StaticGenerator.new(output_dir: public_dir)
    generator.instance_variable_set(:@manifest, generator.send(:load_manifest))
    generator.send(:cleanup_deleted_files)

    # Orphaned file should be removed
    assert_not File.exist?(orphaned_file)
  end

  test "build_content_manifest creates manifest for model" do
    generator = StaticGenerator.new(output_dir: @public_test_dir)

    post1 = create(:post, metadata: { "title" => "Post 1", "status" => "published", "date" => "2024-01-01", "url_name" => "post-1" })
    post2 = create(:post, metadata: { "title" => "Post 2", "status" => "published", "date" => "2024-01-02", "url_name" => "post-2" })

    manifest = generator.send(:build_content_manifest, Post)

    assert manifest.key?(post1.id.to_s)
    assert manifest.key?(post2.id.to_s)
    assert manifest[post1.id.to_s].key?(:updated_at)
    assert manifest[post1.id.to_s].key?(:html_file)
    assert_equal "posts/post-1.html", manifest[post1.id.to_s][:html_file]
  end

  test "detect_changes returns hash of changes" do
    generator = StaticGenerator.new(output_dir: @public_test_dir)

    # Create posts
    post = create(:post, metadata: { "title" => "Test", "status" => "published", "date" => "2024-01-01" })
    post.update_column(:updated_at, Time.current)

    # Create manifest with older timestamp
    create_manifest({
      "generated_at" => 2.hours.ago.iso8601,
      "posts" => {
        post.id.to_s => {
          "updated_at" => 2.hours.ago.iso8601,
          "html_file" => "posts/test.html"
        }
      },
      "configs" => {}
    })

    generator.instance_variable_set(:@manifest, generator.send(:load_manifest))
    changes = generator.send(:detect_changes)

    assert changes.key?(:posts)
    assert changes.key?(:pages)
    assert changes.key?(:documentation)
    assert changes.key?(:changed_configs)
  end

  test "generate_all returns stats hash" do
    generator = StaticGenerator.new(output_dir: @public_test_dir)

    # Clear any existing pages that might have nil metadata
    # to avoid rendering errors during test
    Page.delete_all

    # The generator should always return a stats hash, even if
    # there are errors during generation
    stats = generator.generate_all

    assert stats.is_a?(Hash)
    assert stats.key?(:posts)
    assert stats.key?(:pages)
    assert stats.key?(:documentation)
    assert stats.key?(:collections)
    assert stats.key?(:collection_pages)
    assert stats.key?(:errors)
    assert stats.key?(:start_time)
    assert stats.key?(:end_time)

    # Stats should be integers
    assert stats[:posts].is_a?(Integer)
    assert stats[:errors].is_a?(Array)
  end

  test "dir_checksum returns consistent hash for directory" do
    # Create test directory with files
    test_dir = Pathname.new(File.join(@public_test_dir, "test_assets"))
    FileUtils.mkdir_p(test_dir)
    File.write(test_dir.join("file1.txt"), "content1")
    File.write(test_dir.join("file2.txt"), "content2")

    generator = StaticGenerator.new(output_dir: @public_test_dir)
    checksum1 = generator.send(:dir_checksum, test_dir)
    checksum2 = generator.send(:dir_checksum, test_dir)

    # Same directory should produce same checksum
    assert_equal checksum1, checksum2
    assert checksum1.is_a?(Hash)
  end

  test "assets_changed? detects when assets change" do
    public_dir = @public_test_dir

    # Create fonts directory
    fonts_dir = File.join(Rails.root, "site", "system", "assets", "fonts")
    FileUtils.mkdir_p(fonts_dir)
    test_font = File.join(fonts_dir, "TestFont.ttf")
    File.write(test_font, "fake font data")

    # Create manifest with no assets
    create_manifest({ "generated_at" => Time.current.iso8601, "assets" => {} })

    generator = StaticGenerator.new(output_dir: public_dir)
    generator.instance_variable_set(:@manifest, generator.send(:load_manifest))

    assert generator.send(:assets_changed?)
  ensure
    FileUtils.rm_rf(fonts_dir)
  end
end
