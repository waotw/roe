# frozen_string_literal: true

require "test_helper"

# Every RSS item used to carry a 200-character summary and nothing else, so a
# paid feed gave subscribers the same list of links a free one did. Items now
# carry the article, cut at the paywall for anyone who hasn't paid.
class FeedFullContentTest < ActiveSupport::TestCase
  BODY = <<~MD
    The free opening paragraph that anyone may read.

    ```form
    for: paid_content
    text: Members only
    button_text: Upgrade
    ```

    The paid remainder, which must never reach a public feed.
  MD

  def post(audience:, title: "A Post")
    Post.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "#{title.parameterize}.md"),
      content: BODY,
      metadata: { "title" => title, "url_name" => title.parameterize, "status" => "published",
                  "date" => "2026-01-01", "audience" => audience }
    )
  end

  def xml(posts, include_paid: false, teasers: false, format: :rss)
    FeedGenerator.new(
      posts: Array(posts), format: format,
      site_config: { title: "S", description: "D", url: "https://example.com", author: "A" },
      include_paid: include_paid, show_paid_teasers: teasers
    ).generate
  end

  # ── The leak this must not have ────────────────────────────────────────────

  test "a paid post's body never reaches a public feed, even as a preview" do
    feed = xml(post(audience: "paid"), teasers: true)

    assert_includes feed, "free opening paragraph", "the free part is the preview"
    assert_not_includes feed, "paid remainder", "the rest is not"
    assert_includes feed, "for members"
  end

  test "a token-gated feed carries the whole thing" do
    feed = xml(post(audience: "paid"), include_paid: true)

    assert_includes feed, "free opening paragraph"
    assert_includes feed, "paid remainder"
  end

  # ── Free posts ─────────────────────────────────────────────────────────────

  test "a free post carries its full body" do
    feed = xml(post(audience: "everyone"))

    assert_includes feed, "free opening paragraph"
    assert_includes feed, "paid remainder", "nothing is gated on a free post"
  end

  # A free post can still carry a paywall block the author left behind. Drop
  # the gate; keep the words.
  test "a free post's leftover paywall block is not rendered" do
    feed = xml(post(audience: "everyone"))

    assert_not_includes feed, "PAID_CONTENT_GATE"
    assert_not_includes feed, "Members only"
  end

  # ── Which posts appear ─────────────────────────────────────────────────────

  test "teasers off drops paid posts entirely" do
    feed = xml([ post(audience: "everyone", title: "Free One"),
                 post(audience: "paid", title: "Paid One") ])

    assert_includes feed, "Free One"
    assert_not_includes feed, "Paid One", "a site that would rather not advertise gets nothing"
  end

  test "teasers on keeps them as previews" do
    feed = xml([ post(audience: "everyone", title: "Free One"),
                 post(audience: "paid", title: "Paid One") ], teasers: true)

    assert_includes feed, "Free One"
    assert_includes feed, "Paid One"
  end

  # ── Both formats ───────────────────────────────────────────────────────────

  test "rss emits content:encoded" do
    assert_includes xml(post(audience: "everyone")), "content:encoded"
  end

  test "atom emits a content element, and gates it the same way" do
    feed = xml(post(audience: "paid"), teasers: true, format: :atom)

    assert_includes feed, "free opening paragraph"
    assert_not_includes feed, "paid remainder"
  end
end
