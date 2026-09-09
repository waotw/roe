# frozen_string_literal: true

require "test_helper"

# A feed is machine output that leaves the building. Two things were getting
# into it that shouldn't: editor warnings meant for whoever is building the
# site, and an artwork URL that pointed at nothing.
class FeedRenderHygieneTest < ActiveSupport::TestCase
  # dev_warning renders as an inline-styled dashed box. Matched on the wrapper
  # rather than its wording — the copy inside is the site owner's to edit.
  DEV_WARNING = /border:2px dashed/
  def paid_post
    Post.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "frh.md"),
      content: "Free part.\n\n```form\nfor: paid_content\n```\n\nPaid part.",
      metadata: { "title" => "FRH", "url_name" => "frh", "status" => "published",
                  "audience" => "paid", "date" => "2026-01-01" }
    )
  end

  # ── Warnings stay in the browser ─────────────────────────────────────────

  # show_block_warnings? keyed off Rails.env.development? alone, so a feed
  # rendered on a dev machine shipped "Stripe isn't connected" into
  # content:encoded and it arrived in a real reader as part of the article.
  # Warnings only render when Rails.env.development? or it's a preview, and the
  # test environment is neither — so without this stub the assertion below
  # passes whether or not the fix is present. It was the development case that
  # shipped the warning into a reader.
  def in_development
    Rails.env.stubs(:development?).returns(true)
    yield
  ensure
    Rails.env.unstub(:development?)
  end

  test "block warnings are suppressed when rendering for a feed" do
    post = paid_post

    in_development do
      assert_match(DEV_WARNING, post.to_html.to_s,
        "precondition — development renders warnings for a browser")

      assert_no_match(DEV_WARNING, post.to_html(feed: true).to_s,
        "an editor warning reached the feed")
    end
  end

  test "and still appear for an editor preview" do
    post = paid_post

    assert_match(DEV_WARNING, post.to_html(preview: true).to_s,
      "the preview is exactly where these belong")
  end

  # static already suppressed them, but it can't be reused for feeds — it also
  # strips dynamic blocks, and a feed needs the gate marker to split on.
  test "a feed render keeps the paywall gate the generator splits on" do
    post = paid_post

    assert_match("<!-- PAID_CONTENT_GATE -->", post.to_html(feed: true).to_s)
  end

  # The flag is reset in an ensure; without that it leaks into the next render
  # on the same instance and warnings vanish everywhere.
  test "the feed flag doesn't leak into the next render" do
    post = paid_post
    post.to_html(feed: true)

    assert_match(DEV_WARNING, post.to_html(preview: true).to_s,
      "a previous feed render silenced a later preview")
  end

  # ── Artwork resolves to something that exists ────────────────────────────

  def generator(artwork)
    FeedGenerator.new(
      posts: [], format: :podcast,
      site_config: { url: "https://example.com" },
      podcast_config: { "title" => "Show", "artwork" => artwork }
    )
  end

  # PodcastConfigSeeder saves channel art into system/assets/images/ and stores
  # only the filename — that's the contract. Joining it onto the site URL gave
  # https://example.com/art.jpg, which 404s. Apple and Overcast both fall back
  # to no artwork silently, so the show just looked blank.
  test "a bare filename resolves to the system image path" do
    dir = File.join(RoeSitePaths::SITE_PATH, "system", "assets", "images")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "frh-art.jpg"), "bytes")

    url = generator("frh-art.jpg").send(:image_full_url, "frh-art.jpg")

    assert_equal "https://example.com/system/images/frh-art.jpg", url
  ensure
    FileUtils.rm_f(File.join(dir, "frh-art.jpg"))
  end

  # Either location works: a bare filename is a system asset, a path is taken
  # as written — so artwork can live in media/ or system/assets/images/.
  test "artwork can come from media as well as system assets" do
    url = generator("/media/images/show-cover.jpg").send(:image_full_url, "/media/images/show-cover.jpg")

    assert_equal "https://example.com/media/images/show-cover.jpg", url
  end

  # No variant for podcast artwork.
  #
  # Apple wants a square JPEG or PNG between 1400 and 3000 pixels and the
  # artwork was chosen to meet that. Variants also live under
  # media/images/variants/, which Site Sync excludes and ContentSync prunes —
  # so a feed could advertise a URL that resolves when the feed renders and
  # 404s when Apple fetches it days later.
  # Structural rather than policed by a regex: the capability is gone, so a
  # future caller can't route artwork through the variant pipeline by passing
  # a keyword.
  test "there is no way to ask for a variant" do
    assert_raises(ArgumentError) do
      generator("x.jpg").send(:image_full_url, "x.jpg", variant: :xl)
    end
  end

  test "a variant path is never emitted for artwork" do
    dir = File.join(RoeSitePaths::SITE_PATH, "media", "images")
    FileUtils.mkdir_p(File.join(dir, "variants"))
    File.write(File.join(dir, "cover.jpg"), "bytes")
    File.write(File.join(dir, "variants", "cover-xl.jpg"), "bytes")

    url = generator("/media/images/cover.jpg").send(:image_full_url, "/media/images/cover.jpg")

    assert_equal "https://example.com/media/images/cover.jpg", url
    assert_no_match(/variants/, url)
  ensure
    FileUtils.rm_f([ File.join(dir, "cover.jpg"), File.join(dir, "variants", "cover-xl.jpg") ])
  end

  # Music covers are written as /media/images/… and must not be rewritten.
  test "a real path is left alone" do
    url = generator("/media/images/cover.jpg").send(:image_full_url, "/media/images/cover.jpg")

    assert_equal "https://example.com/media/images/cover.jpg", url
  end

  # A stale entry keeps its old behaviour rather than gaining a confidently
  # wrong URL.
  test "a filename with no matching asset falls through" do
    url = generator("missing.jpg").send(:image_full_url, "missing.jpg")

    assert_equal "https://example.com/missing.jpg", url
  end
end
