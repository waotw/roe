require "test_helper"

# Every media post shows one player at the top: the post type's own, or the
# ```card type: player in its body, never both. The template's player is the
# same card (except podcasts, which keep their full player for now), and
# content.yml's players.video / players.audio can turn the automatic one off.
class PostPlayerTest < ActionDispatch::IntegrationTest
  CARD = "```card\ntype: player\n```".freeze

  def media_post(type, content: "Words.", **fields)
    @n = (@n || 0) + 1
    create(:post,
      metadata: { "title" => "#{type.capitalize} post #{@n}", "status" => "published", "date" => "2024-01-01",
                  "audience" => "everyone", "post_type" => type }.merge(fields.transform_keys(&:to_s)),
      content: content)
  end

  def card_players = css_select(".card-player").size
  def iframes = css_select("iframe").size

  # ── video ──

  test "a video post without a card in its body gets the player card at the top" do
    post = media_post("video", video: "https://youtu.be/dQw4w9WgXcQ", duration: "00:03:33")

    get post_path(post.url_name)
    assert_equal 1, card_players
    assert_equal 1, iframes
    assert_select ".media-meta .duration", "00:03:33"
  end

  test "a video post with its own card shows only that one" do
    post = media_post("video", video: "https://youtu.be/dQw4w9WgXcQ", duration: "00:03:33", content: "#{CARD}\n\nWords.")

    get post_path(post.url_name)
    assert_equal 1, card_players, "one player, not two"
    assert_equal 1, iframes
    assert_select ".post-content .card-player"
    assert_select ".media-meta", 0, "the duration line belongs to the template's player"
  end

  # ── audio and music ──

  %w[audio music].each do |type|
    test "an #{type} post gets the player card, or keeps its own" do
      post = media_post(type, audio: "/media/audio/track.mp3")
      get post_path(post.url_name)
      assert_equal 1, card_players
      assert_select ".card-player audio source[src='/media/audio/track.mp3']", minimum: 1

      own = media_post(type, audio: "/media/audio/track.mp3", content: "Intro.\n\n#{CARD}")
      get post_path(own.url_name)
      assert_equal 1, card_players
      assert_select ".post-content .card-player"
    end
  end

  test "the bare browser audio bar is gone from audio posts" do
    post = media_post("audio", audio: "/media/audio/track.mp3")

    get post_path(post.url_name)
    assert_select "audio[controls]", 0
  end

  # ── podcast ──

  test "a podcast keeps its full player, unless the body has a player card" do
    post = media_post("podcast", audio: "/media/audio/ep.mp3", duration: "00:30:00")
    get post_path(post.url_name)
    assert_select ".podcast-hero .audio-player", 1
    assert_equal 0, card_players

    own = media_post("podcast", audio: "/media/audio/ep.mp3", duration: "00:30:00", content: "#{CARD}\n\nNotes.")
    get post_path(own.url_name)
    assert_select ".podcast-hero", 0
    assert_equal 1, card_players
  end

  # ── nothing to play, other types ──

  test "a media post with nothing to play shows no player" do
    post = media_post("audio")

    get post_path(post.url_name)
    assert_equal 0, card_players
  end

  test "an article never gets one" do
    post = media_post("article", audio: "/media/audio/track.mp3")

    get post_path(post.url_name)
    assert_equal 0, card_players
  end

  # ── content.yml ──

  test "players.video: false turns off the automatic video player, and only that" do
    SiteConfig.stubs(:content).returns(nil)
    SiteConfig.stubs(:content).with("players.video").returns(false)

    get post_path(media_post("video", video: "https://youtu.be/dQw4w9WgXcQ").url_name)
    assert_equal 0, card_players

    get post_path(media_post("audio", audio: "/media/audio/track.mp3").url_name)
    assert_equal 1, card_players, "audio still has its player"
  end

  test "players.audio: false covers audio, music and podcasts; a card in the body still shows" do
    SiteConfig.stubs(:content).returns(nil)
    SiteConfig.stubs(:content).with("players.audio").returns("false")

    %w[audio music].each do |type|
      get post_path(media_post(type, audio: "/media/audio/track.mp3").url_name)
      assert_equal 0, card_players, type
    end
    get post_path(media_post("podcast", audio: "/media/audio/ep.mp3", duration: "1").url_name)
    assert_select ".podcast-hero", 0

    get post_path(media_post("audio", audio: "/media/audio/track.mp3", content: CARD).url_name)
    assert_equal 1, card_players, "the setting is about the automatic player, not the author's"
  end

  # ── recognising the card ──

  test "only a real player card in the body counts" do
    assert Post.new(content: "```card\ntype: player\n```").player_card_in_body?
    assert Post.new(content: "Text\n\n  ```card\n  title: A\n  type: \"player\"\n  ```").player_card_in_body?
    assert_not Post.new(content: "```card\ntype: pullquote\ntext: type: player\n```").player_card_in_body?
    assert_not Post.new(content: "type: player").player_card_in_body?
    assert_not Post.new(content: "```collection\ntype: player\n```").player_card_in_body?
  end
end
