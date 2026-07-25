require "test_helper"

# CollectionQuery is the shared selection behind collections and (soon) feeds.
# The filtering assertions compare against the raw scopes the query is built
# from, so they prove equivalence against whatever content the test site holds
# rather than depending on specific fixtures.
class CollectionQueryTest < ActiveSupport::TestCase
  setup { @created = [] }
  teardown { @created.each { |f| File.delete(f) if File.exist?(f) } }

  def write_post(name, extra = {})
    meta = { "title" => name.tr("-", " "), "url_name" => name, "status" => "published" }.merge(extra)
    slug = ContentWriter.new.write(kind: :post, filename: name, metadata: meta, body: "x")
    @created << File.join(RoeSitePaths::SITE_POSTS_PATH, "#{slug}.md")
    slug
  end

  # --- source_for --------------------------------------------------------

  test "source_for defaults to posts, but a menu with no source defaults to pages" do
    assert_equal "posts", CollectionQuery.source_for({})
    assert_equal "pages", CollectionQuery.source_for(template: "menu")
    assert_equal "products", CollectionQuery.source_for(source: "products", template: "menu")
  end

  # --- normalize_names ---------------------------------------------------

  test "normalize_names downcases, trims, dedupes, drops blanks (string or array)" do
    assert_equal %w[nav footer], CollectionQuery.normalize_names(" Nav , footer , nav ,")
    assert_equal %w[nav footer], CollectionQuery.normalize_names([ "Nav", "FOOTER", "nav" ])
  end

  # --- records: unknown source ------------------------------------------

  test "records is nil for an unknown source (caller warns/renders empty)" do
    assert_nil CollectionQuery.new(source: "widgets").records
  end

  # --- records: filters match the raw scopes ----------------------------

  test "records for posts equals the published, regular scope" do
    expected = Post.published.regular_posts.pluck(:id).sort
    actual   = CollectionQuery.new(source: "posts").records.to_a.map(&:id).sort
    assert_equal expected, actual
  end

  test "post_type filters identically to by_type" do
    type = Post.published.regular_posts.first&.post_type || "article"
    expected = Post.published.regular_posts.by_type(type).pluck(:id).sort
    actual   = CollectionQuery.new(source: "posts", post_type: type).records.to_a.map(&:id).sort
    assert_equal expected, actual
  end

  test "post_type: all is treated as no filter" do
    expected = Post.published.regular_posts.pluck(:id).sort
    actual   = CollectionQuery.new(source: "posts", post_type: "all").records.to_a.map(&:id).sort
    assert_equal expected, actual
  end

  test "a positive tag includes only tagged posts; a negative tag excludes them" do
    write_post("cq-tagged", "tags" => "cq-topic")
    write_post("cq-untagged")

    positive = CollectionQuery.new(source: "posts", tags: "cq-topic").records.to_a.map(&:url_name)
    assert_includes positive, "cq-tagged"
    assert_not_includes positive, "cq-untagged"

    negative = CollectionQuery.new(source: "posts", tags: "-cq-topic").records.to_a.map(&:url_name)
    assert_not_includes negative, "cq-tagged", "negative tag removes the tagged post"
    assert_includes negative, "cq-untagged", "but keeps the untagged one"
  end

  # --- records: collection membership -----------------------------------

  test "a collection: name filter selects only members (and returns an Array)" do
    write_post("cq-member", "collection" => "cq-fixture")

    records = CollectionQuery.new(source: "posts", collection: "cq-fixture").records

    assert_kind_of Array, records, "membership selection is Ruby-side, so an Array"
    assert records.any? { |p| p.url_name == "cq-member" }, "the member is included"
    assert records.all? { |p| p.collection_names.include?("cq-fixture") }, "only members"
  end
end
