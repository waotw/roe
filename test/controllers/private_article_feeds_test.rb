# frozen_string_literal: true

require "test_helper"

# Podcasts have had a members' feed since paid episodes existed; articles only
# had the public half, so someone who'd paid still read previews in their
# reader. These are the members' copies.
class PrivateArticleFeedsTest < ActionDispatch::IntegrationTest
  BODY = <<~MD
    The free opening paragraph.

    ```form
    for: paid_content
    text: Members only
    button_text: Upgrade
    ```

    The paid remainder.
  MD

  setup { SiteFeature.stubs(:members_enabled?).returns(true) }

  teardown do
    path = SiteConfig::FEATURES_PATH.join("feeds.yml")
    File.delete(path) if File.exist?(path)
    SiteConfig.reload!("features/feeds")
  end

  def paid_post(title = "Paid One")
    Post.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "#{title.parameterize}.md"),
      content: BODY,
      metadata: { "title" => title, "url_name" => title.parameterize, "status" => "published",
                  "date" => "2026-01-01", "audience" => "paid" }
    )
  end

  def member(tier: :paid, status: :active)
    Member.create!(email: "m#{Member.count}@example.com", name: "M", tier: tier, status: status)
  end

  def write_feed(name, config)
    path = SiteConfig::FEATURES_PATH.join("feeds.yml")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, { name => config }.to_yaml.sub(/\A---\s*\n/, ""))
    SiteConfig.sync_from_file("features/feeds")
  end

  # ── The main feed ──────────────────────────────────────────────────────────

  test "a paid member gets full articles" do
    paid_post

    get "/feed/private.xml", params: { token: member.media_token }

    assert_response :success
    assert_includes response.body, "paid remainder"
  end

  test "the public feed does not, even with previews on" do
    paid_post
    SiteConfig.stubs(:feature).returns(nil)
    SiteConfig.stubs(:feature).with("members", "everyone.show_paid_content").returns(true)

    get "/feed.xml"

    assert_response :success
    assert_not_includes response.body, "paid remainder"
  end

  test "no token, no feed" do
    paid_post

    get "/feed/private.xml"
    assert_response :unauthorized
  end

  test "a free or cancelled member is refused" do
    paid_post

    get "/feed/private.xml", params: { token: member(tier: :free).media_token }
    assert_response :unauthorized

    get "/feed/private.xml", params: { token: member(status: :cancelled).media_token }
    assert_response :unauthorized
  end

  # The sign-in token must not open feeds either — it's the one credential that
  # would hand over the account.
  test "the sign-in token is refused" do
    paid_post

    get "/feed/private.xml", params: { token: member.access_token }
    assert_response :unauthorized
  end

  test "atom works the same way" do
    paid_post

    get "/feed/private.atom", params: { token: member.media_token }

    assert_response :success
    assert_includes response.body, "paid remainder"
  end

  # ── Named feeds ────────────────────────────────────────────────────────────

  test "a named feed has a members' copy" do
    paid_post
    write_feed("articles", { "title" => "Articles", "source" => "posts", "audience" => "free" })

    get "/feed/articles/private.xml", params: { token: member.media_token }

    assert_response :success
    assert_includes response.body, "paid remainder"
  end

  test "an unknown named feed is a 404, not an empty feed" do
    get "/feed/nothing/private.xml", params: { token: member.media_token }
    assert_response :not_found
  end

  # `private` is reserved so a feed by that name can't shadow the main
  # members' copy at /feed/private.xml.
  test "a feed cannot be named private" do
    assert FeedConfig.reserved?("private")
    write_feed("private", { "title" => "Nope", "source" => "posts" })

    assert_nil FeedConfig.get("private")
  end

  # ── Members off ────────────────────────────────────────────────────────────

  test "the routes are closed when members is off" do
    paid_post
    m = member
    SiteFeature.stubs(:members_enabled?).returns(false)

    get "/feed/private.xml", params: { token: m.media_token }
    assert_response :not_found

    get "/feed/articles/private.xml", params: { token: m.media_token }
    assert_response :not_found
  end
end
