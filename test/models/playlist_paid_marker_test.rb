# frozen_string_literal: true

require "test_helper"

# A playlist listed protected tracks with nothing to distinguish them. Their
# audio 403s, so pressing play did nothing and the player looked broken. The
# lock says why up front; the player says it again if you press play anyway.
class PlaylistPaidMarkerTest < ActiveSupport::TestCase
  def track(title, audience: nil, show: nil)
    meta = { "title" => title, "url_name" => title.parameterize, "status" => "published",
             "post_type" => "podcast", "audio" => "/media/audio/#{title.parameterize}.mp3",
             "date" => "2026-01-01" }
    meta["audience"] = audience if audience
    meta["podcast"] = show if show
    Post.create!(file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "#{title.parameterize}.md"),
                 content: "Body.", metadata: meta)
  end

  def playlist
    Page.new(
      file_path: File.join(RoeSitePaths::SITE_PATH, "pages", "list.md"),
      content: "```collection\nsource: posts\npost_type: podcast\ntemplate: playlist\n```",
      metadata: { "title" => "List", "status" => "published" }
    ).to_html
  end

  # Paid items are dropped from a collection entirely unless Show Paid Content
  # is on — which is the configuration where the missing marker actually bites,
  # since that's when a protected track appears in the list at all.
  # Catch-all first: a bare `with` stub leaves other argument combinations
  # unstubbed.
  setup do
    SiteConfig.stubs(:feature_enabled?).returns(false)
    SiteConfig.stubs(:feature_enabled?).with("members").returns(true)
    SiteConfig.stubs(:feature).returns(nil)
    SiteConfig.stubs(:feature).with("members", "everyone.show_paid_content").returns(true)
  end

  test "a paid track is marked, a free one isn't" do
    track("Paid One", audience: "paid")
    track("Free One", audience: "everyone")

    html = playlist

    assert_equal 1, html.scan("paid-lock-icon").size
    assert_includes html, 'data-paid="true"'
    assert_includes html, 'data-paid="false"'
  end

  # The row has to reflect whether the AUDIO is protected, not whether the post
  # says it's paid. An episode on a paid show inherits protection with a blank
  # audience of its own — marking it free would be a lie the 403 then exposes.
  test "a track protected by its show is marked despite a blank audience" do
    PodcastConfig.stubs(:get).returns({ "audience" => "paid" })
    track("Inherited", show: "the-show")

    html = playlist

    assert_includes html, 'data-paid="true"'
    assert_includes html, "paid-lock-icon"
  end

  test "an episode that opts out of a paid show is unmarked" do
    PodcastConfig.stubs(:get).returns({ "audience" => "paid" })
    track("Opener", audience: "everyone", show: "the-show")

    html = playlist

    assert_includes html, 'data-paid="false"'
    assert_not_includes html, "paid-lock-icon"
  end

  # Static builds have no member session and no upgrade flow, so the lock is
  # noise — same rule show_paid_indicator? already follows.
  test "nothing is marked in a static build" do
    track("Paid One", audience: "paid")

    page = Page.new(
      file_path: File.join(RoeSitePaths::SITE_PATH, "pages", "list.md"),
      content: "```collection\nsource: posts\npost_type: podcast\ntemplate: playlist\n```",
      metadata: { "title" => "List", "status" => "published" }
    )

    # to_html sets @rendering_static from this keyword, so it has to come
    # through the real API — setting the ivar first is overwritten.
    assert_not_includes page.to_html(static: true), "paid-lock-icon"
  end

  test "nothing is marked when members are off" do
    SiteConfig.stubs(:feature_enabled?).with("members").returns(false)
    track("Paid One", audience: "paid")

    assert_not_includes playlist, "paid-lock-icon"
  end
end
