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

  # --- ordering ----------------------------------------------------------

  test "order_items sorts by a keyword and by an explicit url_name list" do
    a = write_post("cq-ord-a", "date" => "2026-01-01")
    b = write_post("cq-ord-b", "date" => "2026-03-01")
    items = Post.where("json_extract(metadata, '$.url_name') IN (?, ?)", a, b).to_a

    newest_first = CollectionQuery.order_items(items, "date").map(&:url_name)
    assert_equal [ "cq-ord-b", "cq-ord-a" ], newest_first

    explicit = CollectionQuery.order_items(items, "cq-ord-a, cq-ord-b").map(&:url_name)
    assert_equal [ "cq-ord-a", "cq-ord-b" ], explicit
  end

  test "sort_keyword? recognizes only the known sort modes" do
    assert CollectionQuery.sort_keyword?("date")
    assert CollectionQuery.sort_keyword?("title")
    assert_not CollectionQuery.sort_keyword?("home, blog, store")
  end

  # --- release membership -------------------------------------------------

  test "a release: filter selects only that release's tracks" do
    write_post("cq-track-a", "post_type" => "music", "release" => "summer")
    write_post("cq-track-b", "post_type" => "music", "release" => "winter")

    summer = CollectionQuery.new(source: "posts", post_type: "music", release: "summer")
      .records.to_a.map(&:url_name)

    assert_includes summer, "cq-track-a"
    assert_not_includes summer, "cq-track-b"
  end

  # --- show_unlisted ------------------------------------------------------

  test "show_unlisted widens a posts collection to include unlisted items" do
    write_post("cq-pub", "status" => "published")
    write_post("cq-unl", "status" => "unlisted")

    without = CollectionQuery.new(source: "posts").records.to_a.map(&:url_name)
    assert_includes without, "cq-pub"
    assert_not_includes without, "cq-unl", "unlisted hidden by default"

    with = CollectionQuery.new(source: "posts", show_unlisted: "true").records.to_a.map(&:url_name)
    assert_includes with, "cq-pub"
    assert_includes with, "cq-unl", "shown with show_unlisted: true"
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
