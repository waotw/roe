require "test_helper"

# A feed item is read away from the site: links and images inside it must
# carry the site's address, or many readers can't follow them.
class FeedAbsoluteUrlsTest < ActiveSupport::TestCase
  def generator = FeedGenerator.new(posts: [], site_config: { url: "https://example.test/" })

  test "site-relative links and images get the site's address" do
    html = %(<a href="/posts/x">a</a> <img src="/media/images/a.jpg" srcset="/media/images/a-400.jpg 400w, /media/images/a-800.jpg 800w"> <video poster='/media/p.jpg'></video>)
    out = generator.send(:absolute_urls, html)

    assert_includes out, %(href="https://example.test/posts/x")
    assert_includes out, %(src="https://example.test/media/images/a.jpg")
    assert_includes out, %(srcset="https://example.test/media/images/a-400.jpg 400w, https://example.test/media/images/a-800.jpg 800w")
    assert_includes out, %(poster='https://example.test/media/p.jpg')
  end

  test "full URLs, protocol-relative URLs, anchors and mail links are left alone" do
    html = %(<a href="https://other.test/x">a</a> <img src="//cdn.test/a.jpg"> <a href="#fn:1">1</a> <a href="mailto:a@b.test">m</a>)
    assert_equal html, generator.send(:absolute_urls, html)
  end

  test "a post's feed item and show notes carry absolute internal links, wikilinks included" do
    target = make("fau-target", "Target text.")
    post = make("fau-linker", "See [[posts/fau-target]] and [old](/posts/fau-target).")
    generator = FeedGenerator.new(posts: [ post ], site_config: { url: "https://example.test" })

    [ generator.send(:feed_item_content, post), generator.send(:episode_content_html, post) ].each do |html|
      assert_equal 2, html.scan(%(href="https://example.test#{target.public_url}")).size, html
    end
  end

  setup { @created = [] }
  teardown { @created.each { |path| FileUtils.rm_f(path) } }

  def make(slug, body)
    path = File.join(RoeSitePaths::SITE_POSTS_PATH, "#{slug}.md")
    File.write(path, "---\ntitle: #{slug.titleize}\nstatus: published\ndate: 2024-01-01\n---\n#{body}\n")
    @created << path
    ContentSync.sync_file(path)
    Post.find_by!(file_path: RoeSitePaths.normalize(path))
  end
end
