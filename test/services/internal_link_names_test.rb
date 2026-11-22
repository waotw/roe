require "test_helper"

# Cards, collections and `related:` name items by url_name or by file. Both
# work, and both follow the item when it moves.
class InternalLinkNamesTest < ActiveSupport::TestCase
  setup { @created = [] }
  teardown { @created.each { |path| FileUtils.rm_f(path) } }

  def make(kind, slug, body: "Text for #{slug}.\n", **meta)
    dir = { post: RoeSitePaths::SITE_POSTS_PATH, page: RoeSitePaths::SITE_PAGES_PATH }.fetch(kind)
    path = File.join(dir, "#{slug}.md")
    front = { "title" => slug.titleize, "status" => "published" }.merge(meta.transform_keys(&:to_s))
    File.write(path, "#{front.to_yaml}---\n#{body}")
    @created << path
    ContentSync.sync_file(path)
    (kind == :post ? Post : Page).find_by(file_path: RoeSitePaths.normalize(path))
  end

  def rename_file(record, new_slug)
    source = InternalLinkRewriter.source_for(record)
    new_path = File.join(File.dirname(record.file_path), "#{new_slug}.md")
    @created << new_path
    File.rename(record.file_path, new_path)
    record.update!(file_path: RoeSitePaths.normalize(new_path))
    InternalLinkRewriter.follow(source, record.reload)
  end

  def change_url_name(record, new_name)
    source = InternalLinkRewriter.source_for(record)
    File.write(record.file_path, File.read(record.file_path).sub(/^url_name: .*$/, "url_name: #{new_name}"))
    ContentSync.sync_file(record.file_path)
    InternalLinkRewriter.follow(source, record.reload)
  end

  BLOCKS = <<~MD
    ```card
    type: post-link
    post: %<card>s
    ```

    ```collection
    source: posts
    order: %<order>s
    ```
  MD

  test "a card, a collection's order and related: can name an item by file" do
    target = make(:post, "iln-target", url_name: "iln-address")
    assert_equal target.id, InternalLinks.resolve("posts/iln-target.md").id
    assert_equal target, Post.new.send(:find_post_by_slug, "posts/iln-target")
    assert_equal target, Post.new.send(:find_post_by_slug, "iln-target.md")
    assert_equal target, Post.new.send(:find_post_by_slug, "iln-address"), "url_names still work"

    other = make(:post, "iln-other")
    ordered = CollectionQuery.explicit_order([ other, target ], "posts/iln-target, iln-other")
    assert_equal [ target, other ], ordered
  end

  test "renaming the file updates file names in cards, collections and related:" do
    target = make(:post, "iln-old")
    linker = make(:page, "iln-linker", related: [ "posts/iln-old", "something-else" ],
                  body: format(BLOCKS, card: "posts/iln-old.md", order: "iln-other, posts/iln-old"))

    count = rename_file(target, "iln-new")

    text = File.read(linker.file_path)
    assert_includes text, "post: posts/iln-new.md"
    assert_includes text, "order: iln-other, posts/iln-new"
    assert_includes text, "- posts/iln-new\n"
    assert_includes text, "- something-else"
    assert_equal 3, count
  end

  test "a new url_name updates url_names in cards, collections and related:" do
    target = make(:post, "iln-name", url_name: "iln-before")
    linker = make(:page, "iln-name-linker", related: [ "iln-before" ],
                  body: format(BLOCKS, card: "/posts/iln-before", order: "\"iln-before\", other"))

    change_url_name(target, "iln-after")

    text = File.read(linker.file_path)
    assert_includes text, "post: /posts/iln-after"
    assert_includes text, "order: \"iln-after\", other"
    assert_includes text, "- iln-after"
  end

  test "a url_name that still belongs to something else is left alone" do
    make(:page, "iln-shared-page", url_name: "iln-shared")
    target = make(:post, "iln-shared-post", url_name: "iln-shared")
    linker = make(:page, "iln-shared-linker", body: format(BLOCKS, card: "iln-shared", order: "iln-shared"))

    change_url_name(target, "iln-moved")

    assert_includes File.read(linker.file_path), "post: iln-shared"
  end

  test "examples inside a code block are left alone" do
    target = make(:post, "iln-example", url_name: "iln-ex-before")
    example = "````markdown\n#{format(BLOCKS, card: 'iln-ex-before', order: 'iln-ex-before')}````\n"
    linker = make(:page, "iln-example-linker", body: example)

    change_url_name(target, "iln-ex-after")

    assert_includes File.read(linker.file_path), "post: iln-ex-before"
  end
end
