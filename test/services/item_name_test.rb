require "test_helper"

# One rule for a name, wherever it's written: a url_name first, then a file
# name; a folder narrows it; `.md` means the file.
class ItemNameTest < ActiveSupport::TestCase
  setup { @created = [] }
  teardown { @created.each { |path| FileUtils.rm_f(path) } }

  def make(kind, slug, **meta)
    dir = { post: RoeSitePaths::SITE_POSTS_PATH, page: RoeSitePaths::SITE_PAGES_PATH }.fetch(kind)
    path = File.join(dir, "#{slug}.md")
    front = { "title" => slug.titleize, "status" => "published", "date" => "2024-01-01" }.merge(meta.transform_keys(&:to_s))
    File.write(path, "#{front.to_yaml}---\nText.\n")
    @created << path
    ContentSync.sync_file(path)
    (kind == :post ? Post : Page).find_by(file_path: RoeSitePaths.normalize(path))
  end

  test "a bare name is a url_name first, then a file name" do
    by_address = make(:post, "in-file-a", url_name: "in-shared")
    by_file = make(:post, "in-shared", url_name: "in-something-else")

    assert_equal by_address, ItemName.find("in-shared")
    assert_equal [ by_address, by_file ], ItemName.matches("in-shared"), "and it's unclear"
    assert_equal by_file, ItemName.find("in-shared.md"), ".md means the file"
    assert_equal by_file, ItemName.find("in-something-else")
    assert_equal by_address, ItemName.find("in-file-a"), "a file name no url_name has"
  end

  test "a folder narrows the name to that kind of item" do
    page = make(:page, "in-about-page", url_name: "in-about")
    post = make(:post, "in-about-post", url_name: "in-about")

    assert_equal post, ItemName.find("in-about"), "posts come first, as cards always had it"
    assert_equal page, ItemName.find("/pages/in-about")
    assert_equal page, ItemName.find("pages/in-about")
    assert_equal post, ItemName.find("/posts/in-about-post.md")
  end

  test "an order reads bare names, folders and files alike" do
    home = make(:page, "in-home", url_name: "in-home")
    about = make(:page, "in-about-us", url_name: "in-about")
    store = make(:page, "in-store")
    items = [ store, about, home ]

    assert_equal [ home, about, store ], CollectionQuery.explicit_order(items, "in-home, in-about, in-store")
    assert_equal [ home, about, store ], CollectionQuery.explicit_order(items, "/pages/in-home, in-about-us.md, pages/in-store")
  end

  test "a Markdown link without .md is an address first, then a file" do
    by_file = make(:post, "in-linked-file", url_name: "in-linked-address")
    other = make(:post, "in-other", url_name: "in-linked-file-taken")

    html = InternalLinks.rewrite_file_hrefs(%(<a href="/posts/in-linked-file">a</a> <a href="/posts/in-linked-address">b</a> <a href="/pages/in-nothing">c</a>))

    assert_includes html, %(<a href="/posts/in-linked-address">a</a>), "no post has that address, so it's the file"
    assert_includes html, %(<a href="/posts/in-linked-address">b</a>), "an address stays"
    assert_includes html, %(<a href="/pages/in-nothing">c</a>), "nothing matches: left as written"
    assert other
  end
end
