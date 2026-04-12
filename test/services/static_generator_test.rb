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

  test "manifest created on first run" do
    manifest_path = File.join(@public_test_dir, ".manifest.json")

    generator = StaticGenerator.new(output_dir: @public_test_dir)

    generator.send(:load_or_create_manifest)

    assert File.exist?(manifest_path)
  end

  test "manifest has correct structure" do
    manifest_path = File.join(@public_test_dir, ".manifest.json")

    generator = StaticGenerator.new(output_dir: @public_test_dir)
    generator.send(:load_or_create_manifest)

    manifest = JSON.parse(File.read(manifest_path))

    assert manifest.key?("generated_at")
    assert manifest.key?("posts")
    assert manifest.key?("configs")
    assert manifest.key?("layouts")
    assert manifest.key?("assets")
  end

  test "config change detected" do
    public_dir = @public_test_dir
    manifest_path = File.join(public_dir, ".manifest.json")

    manifest = {
      "generated_at" => 1.hour.ago.to_iso8601,
      "configs" => {
        "site" => 1.hour.ago.to_iso8601
      }
    }
    File.write(manifest_path, JSON.generate(manifest))

    generator = StaticGenerator.new(output_dir: public_dir)

    generator.send(:load_or_create_manifest)

    SiteConfig.create_or_update(file_path: "site/system/global/site.yml", config: { "title" => "Updated" })
    SiteConfig.last.touch

    assert generator.send(:config_file_changed?, "site")
  end

  test "post change only regenerates post" do
    public_dir = @public_test_dir
    manifest_path = File.join(public_dir, ".manifest.json")

    old_time = 1.hour.ago

    post = create(:post, metadata: { "title" => "Test", "status" => "published", "date" => "2024-01-01" })

    manifest = {
      "generated_at" => old_time.to_iso8601,
      "posts" => {
        post.id.to_s => {
          "updated_at" => old_time.to_iso8601,
          "html_file" => "posts/test.html"
        }
      },
      "configs" => {}
    }
    File.write(manifest_path, JSON.generate(manifest))

    generator = StaticGenerator.new(output_dir: public_dir)
    generator.send(:load_or_create_manifest)

    post.touch

    changed_posts = generator.send(:get_changed_posts)

    assert changed_posts.include?(post.id)
  end

  test "unchanged content not regenerated" do
    public_dir = @public_test_dir
    manifest_path = File.join(public_dir, ".manifest.json")

    recent_time = Time.current

    post = create(:post, metadata: { "title" => "Test", "status" => "published", "date" => "2024-01-01" })

    manifest = {
      "generated_at" => recent_time.to_iso8601,
      "posts" => {
        post.id.to_s => {
          "updated_at" => recent_time.to_iso8601,
          "html_file" => "posts/test.html"
        }
      },
      "configs" => {}
    }
    File.write(manifest_path, JSON.generate(manifest))

    generator = StaticGenerator.new(output_dir: public_dir)
    generator.send(:load_or_create_manifest)

    changed_posts = generator.send(:get_changed_posts)

    refute changed_posts.include?(post.id)
  end

  test "generates correct output directory structure" do
    public_dir = @public_test_dir

    generator = StaticGenerator.new(output_dir: public_dir)

    FileUtils.mkdir_p(File.join(public_dir, "posts"))

    generator.send(:ensure_directories)

    assert Dir.exist?(File.join(public_dir, "posts"))
  end

  test "handles missing content gracefully" do
    public_dir = @public_test_dir

    generator = StaticGenerator.new(output_dir: public_dir)

    empty_result = generator.send(:render_empty_collection, "No posts")

    assert empty_result.include?("No posts")
  end

  test "post url generation for regular posts" do
    post = create(:post, metadata: {
      "title" => "Test Post",
      "status" => "published",
      "date" => "2024-01-15",
      "url_name" => "test-post"
    })

    generator = StaticGenerator.new(output_dir: @public_test_dir)
    url = generator.send(:post_url, post)

    assert_equal "/posts/test-post", url
  end

  test "post url generation falls back to date path" do
    post = create(:post, metadata: {
      "title" => "Dated Post",
      "status" => "published",
      "date" => "2024-01-15",
      "url_name" => "dated-post"
    })

    generator = StaticGenerator.new(output_dir: @public_test_dir)

    generator.stubs(:use_date_urls?).returns(true)
    url = generator.send(:post_url, post)

    assert url.include?("2024")
    assert url.include?("dated-post")
  end

  test "generates posts index path" do
    generator = StaticGenerator.new(output_dir: @public_test_dir)

    index_path = generator.send(:posts_index_path, 1)

    assert_equal "posts.html", index_path
  end

  test "generates paginated posts index path" do
    generator = StaticGenerator.new(output_dir: @public_test_dir)

    index_path = generator.send(:posts_index_path, 2)

    assert_equal "posts/page-2.html", index_path
  end

  test "collection path generation" do
    generator = StaticGenerator.new(output_dir: @public_test_dir)

    collection_path = generator.send(:collection_path, "ruby")

    assert_equal "collections/ruby.html", collection_path
  end

  test "handles post_type in collection path" do
    generator = StaticGenerator.new(output_dir: @public_test_dir)

    collection_path = generator.send(:collection_path, nil, "article")

    assert collection_path.include?("article")
  end

  test "copies font assets" do
    fonts_dir = File.join(Rails.root, "site", "system", "assets", "fonts")
    FileUtils.mkdir_p(fonts_dir)
    test_font = File.join(fonts_dir, "TestFont.ttf")
    File.write(test_font, "fake font data")

    generator = StaticGenerator.new(output_dir: @public_test_dir)

    generator.send(:copy_assets)

    assert File.exist?(File.join(@public_test_dir, "assets", "fonts", "TestFont.ttf"))
  ensure
    FileUtils.rm_rf(fonts_dir)
  end

  test "incremental build only regenerates changed pages" do
    public_dir = @public_test_dir
    manifest_path = File.join(public_dir, ".manifest.json")

    post1 = create(:post, metadata: { "title" => "Post 1", "status" => "published", "date" => "2024-01-01" })
    post2 = create(:post, metadata: { "title" => "Post 2", "status" => "published", "date" => "2024-01-02" })

    manifest = {
      "generated_at" => Time.current.to_iso8601,
      "posts" => {
        post1.id.to_s => {
          "updated_at" => 1.hour.ago.to_iso8601,
          "html_file" => "posts/post-1.html"
        },
        post2.id.to_s => {
          "updated_at" => 1.hour.ago.to_iso8601,
          "html_file" => "posts/post-2.html"
        }
      },
      "configs" => {}
    }
    File.write(manifest_path, JSON.generate(manifest))

    generator = StaticGenerator.new(output_dir: public_dir)
    generator.send(:load_or_create_manifest)

    post1.touch

    changed = generator.send(:get_changed_posts)

    assert changed.include?(post1.id)
    refute changed.include?(post2.id)
  end

  test "config change triggers full regeneration flag" do
    public_dir = @public_test_dir
    manifest_path = File.join(public_dir, ".manifest.json")

    manifest = {
      "generated_at" => 1.hour.ago.to_iso8601,
      "configs" => {
        "site" => 1.hour.ago.to_iso8601
      }
    }
    File.write(manifest_path, JSON.generate(manifest))

    generator = StaticGenerator.new(output_dir: public_dir)
    generator.send(:load_or_create_manifest)

    SiteConfig.create_or_update(file_path: "site/system/global/site.yml", config: { "title" => "New" })
    SiteConfig.last.touch

    assert generator.send(:full_regeneration_required?)
  end
end
