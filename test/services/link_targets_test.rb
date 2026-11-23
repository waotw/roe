require "test_helper"

# What a reference points at, as the page reads it: addresses through the
# routes (redirect routes and other pages left alone), media in the folders
# media is served from.
class LinkTargetsTest < ActiveSupport::TestCase
  setup { @created = [] }
  teardown { @created.each { |f| File.delete(f) if File.exist?(f) } }

  def make(kind, name, status: "published")
    meta = { "title" => name.titleize, "status" => status, "date" => "2024-01-01" }
    meta["post_type"] = "article" if kind == :post
    slug = ContentWriter.new.write(kind: kind, filename: name, metadata: meta, body: "body")
    dir = kind == :post ? RoeSitePaths::SITE_POSTS_PATH : RoeSitePaths::SITE_PAGES_PATH
    path = File.join(dir, "#{slug}.md")
    @created << path
    ContentSync.sync_file(path)
  end

  test "a post or page address is checked against its url_name" do
    make(:post, "lt-live")
    make(:post, "lt-later", status: "draft")
    make(:page, "lt-page")

    assert_equal :ok, LinkTargets.address_status("/posts/lt-live#notes").first
    assert_equal :draft, LinkTargets.address_status("/posts/lt-later").first
    assert_equal :missing, LinkTargets.address_status("/posts/lt-nothing").first
    assert_equal :ok, LinkTargets.address_status("/lt-page").first
    assert_equal :missing, LinkTargets.address_status("/lt-no-page").first
  end

  test "addresses that aren't a post, page, product or doc aren't judged" do
    assert_equal :ok, LinkTargets.address_status("/feed.xml").first
    assert_equal :ok, LinkTargets.address_status("/admin").first
    # A redirect route: the pages catch-all would otherwise claim it.
    assert_equal :ok, LinkTargets.address_status("/signup").first
  end

  test "a media path is found in the site's media folder, not outside it" do
    path = File.join(RoeSitePaths::SITE_PATH, "media", "images", "lt-here.jpg")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "x")
    @created << path

    assert LinkTargets.media_exists?("/media/images/lt-here.jpg")
    refute LinkTargets.media_exists?("/media/images/lt-gone.jpg")
    refute LinkTargets.media_exists?("/media/../system/global/site.yml")
  end

  test "a name with a folder that finds nothing there still finds the name, as a card does" do
    make(:post, "lt-named")

    assert_equal 1, LinkTargets.name_matches("pages/lt-named").size
    assert_empty LinkTargets.name_matches("lt-nobody")
  end
end
