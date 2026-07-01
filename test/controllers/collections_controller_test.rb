require "test_helper"

class CollectionsControllerTest < ActionDispatch::IntegrationTest
  def setup
    super

    @ruby_post = create(:post, metadata: {
      "title" => "Ruby Post",
      "status" => "published",
      "date" => "2024-01-15",
      "tags" => [ "ruby", "rails" ]
    })
    @rails_post = create(:post, metadata: {
      "title" => "Rails Post",
      "status" => "published",
      "date" => "2024-01-20",
      "tags" => [ "rails", "web" ]
    })
    @python_post = create(:post, metadata: {
      "title" => "Python Post",
      "status" => "published",
      "date" => "2024-01-25",
      "tags" => [ "python" ]
    })
    @draft = create(:post, metadata: {
      "title" => "Draft Post",
      "status" => "draft",
      "tags" => [ "ruby" ]
    })
  end

  test "index shows all published posts" do
    get "/posts"

    assert_response :success
    assert_includes response.body, "Ruby Post"
    assert_includes response.body, "Rails Post"
    assert_includes response.body, "Python Post"
    refute_includes response.body, "Draft Post"
  end

  test "tag filter uses OR logic" do
    get "/collections/ruby,rails"

    assert_response :success
    assert_includes response.body, "Ruby Post"
    assert_includes response.body, "Rails Post"
    refute_includes response.body, "Python Post"
  end

  test "type filter works" do
    article = create(:post, metadata: {
      "title" => "Article",
      "status" => "published",
      "date" => "2024-02-01",
      "post_type" => "article"
    })
    music = create(:post, metadata: {
      "title" => "Music",
      "status" => "published",
      "date" => "2024-02-02",
      "post_type" => "music"
    })

    get "/collections/type-article"

    assert_response :success
    assert_includes response.body, "Article"
    refute_includes response.body, "Music"
  end

  test "pagination works" do
    25.times do |i|
      create(:post, metadata: {
        "title" => "Post #{i}",
        "status" => "published",
        "date" => "2024-03-#{(i+1).to_s.rjust(2, '0')}"
      })
    end

    get "/posts"
    assert_response :success

    get "/posts?page=2"
    assert_response :success
  end

  test "exclude tags removes posts" do
    archived = create(:post, metadata: {
      "title" => "Archived Post",
      "status" => "published",
      "date" => "2024-01-01",
      "tags" => [ "archived" ]
    })
    active = create(:post, metadata: {
      "title" => "Active Post",
      "status" => "published",
      "date" => "2024-01-02",
      "tags" => [ "active" ]
    })

    get "/posts", params: { exclude: "archived" }

    assert_response :success
    assert_includes response.body, "Active Post"
    refute_includes response.body, "Archived Post"
  end

  test "order by title" do
    create(:post, metadata: { "title" => "Zebra", "status" => "published", "date" => "2024-01-01" })
    create(:post, metadata: { "title" => "Apple", "status" => "published", "date" => "2024-01-02" })

    get "/posts", params: { order: "title" }

    assert_response :success
    body = response.body
    apple_pos = body.index("Apple")
    zebra_pos = body.index("Zebra")
    assert apple_pos < zebra_pos, "Apple should appear before Zebra"
  end

  test "order by date ascending" do
    create(:post, metadata: { "title" => "Older", "status" => "published", "date" => "2024-01-01" })
    create(:post, metadata: { "title" => "Newer", "status" => "published", "date" => "2024-12-31" })

    get "/posts", params: { order: "date-asc" }

    assert_response :success
    body = response.body
    older_pos = body.index("Older")
    newer_pos = body.index("Newer")
    assert older_pos < newer_pos, "Older should appear before Newer"
  end

  test "generates correct heading for tag collection" do
    get "/collections/ruby"

    assert_response :success
    assert_includes response.body, "Ruby"
  end

  test "generates correct heading for type collection" do
    create(:post, metadata: {
      "title" => "Article",
      "status" => "published",
      "date" => "2024-01-01",
      "post_type" => "article"
    })

    get "/collections/type-article"

    assert_response :success
    assert_includes response.body, "Articles"
  end

  test "only published posts in collection" do
    published = create(:post, metadata: {
      "title" => "Published",
      "status" => "published",
      "date" => "2024-01-01"
    })
    unlisted = create(:post, metadata: {
      "title" => "Unlisted",
      "status" => "unlisted",
      "date" => "2024-01-02"
    })
    draft = create(:post, metadata: {
      "title" => "Draft",
      "status" => "draft",
      "date" => "2024-01-03"
    })

    get "/posts"

    assert_response :success
    assert_includes response.body, "Published"
    refute_includes response.body, "Unlisted"
    refute_includes response.body, "Draft"
  end

  test "order by filename extracts numbers" do
    create(:post, file_path: "site/posts/02-second.md", metadata: {
      "title" => "Second",
      "status" => "published",
      "date" => "2024-01-01"
    })
    create(:post, file_path: "site/posts/01-first.md", metadata: {
      "title" => "First",
      "status" => "published",
      "date" => "2024-01-02"
    })

    get "/posts", params: { order: "filename" }

    assert_response :success
    body = response.body
    first_pos = body.index("First")
    second_pos = body.index("Second")
    assert first_pos < second_pos, "First (01) should appear before Second (02)"
  end

  test "collections controller responds to filters" do
    get "/collections"

    assert_response :success
  end

  test "collection with multiple tags" do
    post = create(:post, metadata: {
      "title" => "Multi Tag",
      "status" => "published",
      "date" => "2024-01-01",
      "tags" => [ "ruby", "rails", "tutorial" ]
    })

    get "/collections/ruby,tutorial"

    assert_response :success
    assert_includes response.body, "Multi Tag"
  end

  test "empty collection handled gracefully" do
    get "/collections/nonexistent-tag-xyz"

    assert_response :success
  end

  # Regression: the archive page must honor the global `everyone.show_paid_content`
  # default (like the inline collection block) when the URL has no ?show_paid.
  # The controller used to always pass :show_paid (nil), forcing the filter's
  # per-request override branch and hiding all paid content — so an archive of a
  # paid series (e.g. /collections/journal) came back empty even though the
  # inline block showed it.
  test "archive shows paid posts when the global show-paid default is on and no show_paid param" do
    SiteConfig.stubs(:feature_enabled?).returns(false)
    SiteConfig.stubs(:feature_enabled?).with("members").returns(true)
    SiteConfig.stubs(:feature).returns(nil)
    SiteConfig.stubs(:feature).with("members", "everyone.show_paid_content").returns(true)

    create(:post, metadata: {
      "title" => "Paid Journal Entry",
      "status" => "published",
      "date" => "2024-05-01",
      "tags" => [ "journal" ],
      "audience" => "paid"
    })

    get "/collections/journal"

    assert_response :success
    assert_includes response.body, "Paid Journal Entry"
  end

  test "archive still hides paid posts when the global default is off" do
    SiteConfig.stubs(:feature_enabled?).returns(false)
    SiteConfig.stubs(:feature_enabled?).with("members").returns(true)
    SiteConfig.stubs(:feature).returns(nil)
    SiteConfig.stubs(:feature).with("members", "everyone.show_paid_content").returns(false)

    create(:post, metadata: {
      "title" => "Paid Journal Entry",
      "status" => "published",
      "date" => "2024-05-01",
      "tags" => [ "journal" ],
      "audience" => "paid"
    })

    get "/collections/journal"

    assert_response :success
    refute_includes response.body, "Paid Journal Entry"
  end
end
