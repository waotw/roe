require "test_helper"
require "tmpdir"

class MediaImporterTest < ActiveSupport::TestCase
  setup { @created = [] }
  teardown do
    @created.each { |f| File.delete(f) if File.exist?(f) }
    if @podcast_backup
      path = PodcastConfigSeeder::PODCAST_YML
      @podcast_backup == :absent ? (File.delete(path) if File.exist?(path)) : File.write(path, @podcast_backup)
      SiteConfig.reload!("features/podcast")
    end
  end

  def make_post(name, meta, body)
    slug = ContentWriter.new.write(kind: :post, filename: name, metadata: meta.merge("title" => name), body: body)
    @created << File.join(RoeSitePaths::SITE_POSTS_PATH, "#{slug}.md")
    Post.find_by("json_extract(metadata, '$.url_name') = ?", slug)
  end

  test "scanner finds external media in frontmatter + body, skips local and non-media" do
    make_post(
      "scan-a",
      { "image" => "https://cdn.example.com/cover.jpg",
        "audio" => "https://cdn.example.com/ep.mp3",
        "status" => "draft",
        "source_url" => "https://example.com/some-article" },
      "Body ![x](https://cdn.example.com/inline.png) plus [local](/media/images/y.png)"
    )
    make_post("scan-b", { "image" => "/media/images/local.jpg", "status" => "draft" }, "nothing external")

    refs = MediaImporter::Scanner.scan
    urls = refs.map(&:url)

    assert_includes urls, "https://cdn.example.com/cover.jpg"
    assert_includes urls, "https://cdn.example.com/ep.mp3"
    assert_includes urls, "https://cdn.example.com/inline.png"
    assert_not_includes urls, "/media/images/local.jpg", "local path skipped"
    assert_not_includes urls, "https://example.com/some-article", "non-media http skipped"

    mine = refs.select { |r| r.record.metadata["url_name"].to_s.start_with?("scan-") }
    by_type = mine.group_by(&:type)
    assert_equal 2, by_type[:images].map(&:url).uniq.size, "cover + inline"
    assert_equal 1, by_type[:audio].map(&:url).uniq.size, "the mp3"

    summary = MediaImporter::Scanner.summary(mine)
    assert_equal({ urls: 2, records: 1 }, summary[:images])
    assert_equal({ urls: 1, records: 1 }, summary[:audio])
  end

  test "fetcher downloads to the right bucket and dedupes identical bytes" do
    Dir.mktmpdir do |media|
      fetcher = MediaImporter::Fetcher.new(media_root: media)
      fetcher.stubs(:download).returns([ "IMGDATA", "image/jpeg" ])

      path = fetcher.fetch("https://cdn.example.com/pic.jpg", :images)
      assert_equal "/media/images/pic.jpg", path
      assert_equal "IMGDATA", File.binread(File.join(media, "images", "pic.jpg"))

      assert_equal "/media/images/pic.jpg", fetcher.fetch("https://cdn.example.com/pic.jpg", :images),
                   "identical bytes reuse the file"

      fetcher.stubs(:download).returns([ "DIFFERENT", "image/jpeg" ])
      assert_equal "/media/images/pic-2.jpg",
                   fetcher.fetch("https://cdn.example.com/other/pic.jpg", :images),
                   "same basename, different bytes disambiguates"
    end
  end

  test "scanner finds external podcast.yml artwork, and rewrite localizes it in the config" do
    path = PodcastConfigSeeder::PODCAST_YML
    @podcast_backup = File.exist?(path) ? File.read(path) : :absent
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, { "myshow" => { "title" => "My Show", "artwork" => "https://cdn.example.com/art.jpg" } }.to_yaml.sub(/\A---\s*\n/, ""))
    SiteConfig.reload!("features/podcast")

    art = MediaImporter::Scanner.scan.find { |r| r.url == "https://cdn.example.com/art.jpg" }
    assert art, "external podcast artwork scanned"
    assert_equal :images, art.type

    assert MediaImporter.rewrite_file(art.record, { "https://cdn.example.com/art.jpg" => "/media/images/art.jpg" })
    assert_includes File.read(path), "/media/images/art.jpg"
    assert_not_includes File.read(path), "https://cdn.example.com/art.jpg"
  end

  test "fetcher infers an extension from content-type when the URL has none" do
    Dir.mktmpdir do |media|
      fetcher = MediaImporter::Fetcher.new(media_root: media)
      fetcher.stubs(:download).returns([ "AUDIO", "audio/mpeg" ])
      path = fetcher.fetch("https://cdn.example.com/play?id=42", :audio)
      assert path.end_with?(".mp3"), "extension from content-type: #{path}"
    end
  end

  test "job downloads selected types, rewrites their refs, leaves others external" do
    media_before = Dir[File.join(RoeSitePaths::SITE_PATH, "media", "**", "*")]
    make_post(
      "job-a",
      { "image" => "https://cdn.example.com/cover.jpg", "status" => "draft" },
      "![x](https://cdn.example.com/inline.png) and [ep](https://cdn.example.com/ep.mp3)"
    )
    MediaImporter::Fetcher.any_instance.stubs(:download).returns([ "BYTES", "image/jpeg" ])

    MediaImportJob.perform_now([ "images" ])

    content = File.read(File.join(RoeSitePaths::SITE_POSTS_PATH, "job-a.md"))
    assert_not_includes content, "https://cdn.example.com/cover.jpg", "image frontmatter rewritten"
    assert_not_includes content, "https://cdn.example.com/inline.png", "body image rewritten"
    assert_includes content, "/media/images/cover.jpg", "rewritten to the local path"
    assert_includes content, "https://cdn.example.com/ep.mp3", "audio not selected → left external"
  ensure
    (Dir[File.join(RoeSitePaths::SITE_PATH, "media", "**", "*")] - media_before)
      .select { |f| File.file?(f) }.each { |f| File.delete(f) }
  end
end
