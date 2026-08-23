# frozen_string_literal: true

require "test_helper"

# A podcast marked paid used to leave every episode's MP3 public. The
# show-level audience only 404'd the public feed and hid the RSS links — it
# stopped advertising the URLs without protecting the files, which is the exact
# obscurity-not-access-control problem the media work exists to fix.
#
# Resolution follows every other default in Roe: the episode's own value wins,
# then its show, then free. So the first three of a paid series can be free.
class InheritedMediaAudienceTest < ActiveSupport::TestCase
  def episode(audience: nil, show: "the-show")
    meta = { "title" => "Ep", "url_name" => "ep", "status" => "published",
             "post_type" => "podcast", "podcast" => show,
             "audio" => "/media/audio/ep.mp3" }
    meta["audience"] = audience unless audience.nil?
    Post.new(file_path: "posts/ep.md", content: "x", metadata: meta)
  end

  def track(audience: nil, release: "summer")
    meta = { "title" => "T", "url_name" => "t", "status" => "published",
             "post_type" => "music", "release" => release,
             "audio" => "/media/audio/t.mp3" }
    meta["audience"] = audience unless audience.nil?
    Post.new(file_path: "posts/t.md", content: "x", metadata: meta)
  end

  def show_audience(value)
    PodcastConfig.stubs(:get).returns({ "audience" => value })
  end

  # ── Podcasts ───────────────────────────────────────────────────────────────

  test "an episode with no audience takes its show's" do
    show_audience("paid")

    assert_equal "paid", episode.media_audience
  end

  test "a free show leaves its episodes free" do
    show_audience("everyone")

    assert_equal "free", episode.media_audience
  end

  # The reason for the whole override rule: a paid series with free openers.
  test "an episode can be free on a paid show" do
    show_audience("paid")

    assert_equal "free", episode(audience: "everyone").media_audience
  end

  test "an episode can be paid on a free show" do
    show_audience("everyone")

    assert_equal "paid", episode(audience: "paid").media_audience
  end

  test "an episode belonging to no show falls back to free" do
    PodcastConfig.stubs(:get).returns(nil)

    assert_equal "free", episode(show: "").media_audience
  end

  # ── Music releases, same shape ─────────────────────────────────────────────

  test "a track with no audience takes its release's" do
    ReleaseConfig.stubs(:audience_for).returns("paid")

    assert_equal "paid", track.media_audience
  end

  test "a track can be free on a paid release" do
    ReleaseConfig.stubs(:audience_for).returns("paid")

    assert_equal "free", track(audience: "everyone").media_audience
  end

  # ── Everything else is unaffected ──────────────────────────────────────────

  test "an ordinary article reads its own audience only" do
    article = Post.new(file_path: "posts/a.md", content: "x",
      metadata: { "title" => "A", "post_type" => "article", "audience" => "paid" })

    assert_equal "paid", article.media_audience
    assert_equal "free", Post.new(file_path: "posts/b.md", content: "x",
      metadata: { "title" => "B", "post_type" => "article" }).media_audience
  end

  # A blank string is what the editor writes for a field nobody filled in — it
  # has to read as "inherit", not as an override meaning free.
  test "a blank audience inherits rather than overriding" do
    show_audience("paid")

    assert_equal "paid", episode(audience: "").media_audience
    assert_equal "paid", episode(audience: "   ").media_audience
  end
end
