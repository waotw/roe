require "test_helper"

# The `template: playlist` collection renders each audio post as a native
# <audio controls> row, with a release/podcast header when scoped. Works for
# music tracks and podcast episodes alike.
class PlayerTemplateTest < ActiveSupport::TestCase
  setup { @created = [] }
  teardown { @created.each { |f| File.delete(f) if File.exist?(f) } }

  def write_post(name, extra = {})
    meta = { "title" => name.tr("-", " "), "url_name" => name, "status" => "published" }.merge(extra)
    slug = ContentWriter.new.write(kind: :post, filename: name, metadata: meta, body: "x")
    @created << File.join(RoeSitePaths::SITE_POSTS_PATH, "#{slug}.md")
    slug
  end

  def render_body(md)
    slug = ContentWriter.new.write(kind: :post, filename: "player-host",
      metadata: { "title" => "Host", "url_name" => "player-host", "status" => "published" }, body: md)
    @created << File.join(RoeSitePaths::SITE_POSTS_PATH, "#{slug}.md")
    Post.find_by("json_extract(metadata, '$.url_name') = ?", slug).to_html
  end

  test "a track's own image is carried on each playlist row" do
    write_post("pt-img", "post_type" => "music", "release" => "im", "audio" => "/media/y.mp3", "image" => "/media/images/track.jpg")

    html = render_body("```collection\ntemplate: playlist\nsource: posts\npost_type: music\nrelease: im\n```")

    assert_includes html, %(data-image="/media/images/track.jpg")
  end

  test "template: player is an alias for playlist (the list)" do
    write_post("pa-one", "post_type" => "music", "release" => "al", "audio" => "/media/al/01.mp3")

    html = render_body("```collection\ntemplate: player\nsource: posts\npost_type: music\nrelease: al\n```")

    assert_includes html, "player-tracks"
    assert_not_includes html, "player-transport", "the transport is a card now, not the collection template"
  end

  test "player card: show_artwork false omits the figure" do
    slug = ContentWriter.new.write(kind: :post, filename: "pc-noart",
      metadata: { "title" => "Ep", "url_name" => "pc-noart", "status" => "published", "audio" => "/media/e.mp3" },
      body: "```card\ntype: player\nshow_artwork: false\n```")
    @created << File.join(RoeSitePaths::SITE_POSTS_PATH, "#{slug}.md")

    html = Post.find_by("json_extract(metadata, '$.url_name') = ?", slug).to_html

    assert_includes html, "card-player"
    assert_not_includes html, "player-figure"
  end

  test "player card renders the transport even without audio (to adopt a playlist)" do
    slug = ContentWriter.new.write(kind: :post, filename: "pc-empty",
      metadata: { "title" => "Page", "url_name" => "pc-empty", "status" => "published" },
      body: "```card\ntype: player\n```")
    @created << File.join(RoeSitePaths::SITE_POSTS_PATH, "#{slug}.md")

    html = Post.find_by("json_extract(metadata, '$.url_name') = ?", slug).to_html

    assert_includes html, "card-player"
    assert_includes html, %(data-controller="audio-player")
    assert_not_includes html, "<source", "no audio source when the post has none"
  end

  test "playlist renders just the track list, no transport" do
    write_post("pl-one", "post_type" => "music", "release" => "pl", "audio" => "/media/pl/01.mp3", "track_number" => 1)
    write_post("pl-two", "post_type" => "music", "release" => "pl", "audio" => "/media/pl/02.mp3", "track_number" => 2)

    html = render_body("```collection\ntemplate: playlist\nsource: posts\npost_type: music\nrelease: pl\n```")

    assert_includes html, "player-tracks"
    assert_includes html, %(src="/media/pl/01.mp3")
    assert_includes html, "player-track-link"
    assert_not_includes html, "player-transport", "playlist has no transport"
    assert_not_includes html, "player-now"
    assert_not_includes html, "collection-player"
  end

  test "player card uses the post's audio + association artwork, wired to audio-player" do
    slug = ContentWriter.new.write(kind: :post, filename: "pc-host",
      metadata: { "title" => "Episode One", "url_name" => "pc-host", "status" => "published",
                  "post_type" => "podcast", "podcast" => "myshow", "audio" => "/media/ep1.mp3" },
      body: "```card\ntype: player\n```")
    @created << File.join(RoeSitePaths::SITE_POSTS_PATH, "#{slug}.md")
    PodcastConfig.stubs(:get).with("myshow").returns({ "title" => "My Show", "artwork" => "art.jpg" })

    html = Post.find_by("json_extract(metadata, '$.url_name') = ?", slug).to_html

    assert_includes html, "card-player"
    assert_includes html, %(data-controller="audio-player")
    assert_includes html, %(<source src="/media/ep1.mp3")
    assert_includes html, %(data-audio-player-target="playButton")
    assert_includes html, "Episode One", "post title in the player"
    assert_includes html, %(src="/system/images/art.jpg"), "artwork from the post's podcast association"
  end

  test "player card honors an explicit audio and title" do
    slug = ContentWriter.new.write(kind: :post, filename: "pc-host2",
      metadata: { "title" => "Host", "url_name" => "pc-host2", "status" => "published" },
      body: "```card\ntype: player\naudio: /media/custom.mp3\ntitle: Custom\n```")
    @created << File.join(RoeSitePaths::SITE_POSTS_PATH, "#{slug}.md")

    html = Post.find_by("json_extract(metadata, '$.url_name') = ?", slug).to_html

    assert_includes html, %(<source src="/media/custom.mp3")
    assert_includes html, "Custom"
  end

  test "a music post without audio is skipped from the playlist" do
    write_post("pt-has-audio", "post_type" => "music", "release" => "s2", "audio" => "/media/a.mp3")
    write_post("pt-no-audio", "post_type" => "music", "release" => "s2")

    html = render_body("```collection\ntemplate: playlist\nsource: posts\npost_type: music\nrelease: s2\n```")

    assert_includes html, "/media/a.mp3"
    assert_not_includes html, "pt-no-audio", "no audio → no row"
  end
end
