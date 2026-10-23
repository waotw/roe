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

  test "a video post without a card in its body gets the player card at the top, without a duration" do
    post = media_post("video", video: "https://youtu.be/dQw4w9WgXcQ", duration: "00:03:33")

    get post_path(post.url_name)
    assert_equal 1, card_players
    assert_equal 1, iframes
    assert_select ".duration", 0, "the duration is the card's show_duration, off by default"
  end

  test "a video post with its own card shows only that one" do
    post = media_post("video", video: "https://youtu.be/dQw4w9WgXcQ", duration: "00:03:33", content: "#{CARD}\n\nWords.")

    get post_path(post.url_name)
    assert_equal 1, card_players, "one player, not two"
    assert_equal 1, iframes
    assert_select ".post-content .card-player"
  end

  # ── show_duration ──

  test "show_duration: true shows the post's length under the player, trimmed of zero hours" do
    card = "```card\ntype: player\nshow_duration: true\n```"
    get post_path(media_post("video", video: "https://youtu.be/dQw4w9WgXcQ", duration: "00:03:33", content: card).url_name)
    assert_select ".card-player .player-duration .duration", "3:33"

    get post_path(media_post("audio", audio: "/media/audio/a.mp3", duration: "01:02:03", content: card).url_name)
    assert_select ".card-player .player-duration .duration", "1:02:03"
  end

  test "show_duration with no length to show draws nothing" do
    card = "```card\ntype: player\nshow_duration: true\n```"
    get post_path(media_post("audio", audio: "/media/audio/a.mp3", content: card).url_name)
    assert_select ".player-duration", 0
  end

  test "a card's own duration wins over the post's" do
    card = "```card\ntype: player\naudio: /media/audio/other.mp3\nduration: 125\nshow_duration: true\n```"
    get post_path(media_post("audio", audio: "/media/audio/a.mp3", duration: "00:30:00", content: card).url_name)
    assert_select ".player-duration .duration", "2:05"
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

  test "an audio post's browser bar is the player card's own, for player.js to replace" do
    post = media_post("audio", audio: "/media/audio/track.mp3")

    get post_path(post.url_name)
    assert_select "audio[controls]", 1
    assert_select ".card-player audio[controls][data-player-part=media]", 1
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

  # A podcast with both video and audio used to print "Audio available:
  # here" under the video. It ignored the player rules above, so it stayed
  # even under the body's own player card. To offer the audio, the post
  # links it.
  test "a podcast with video and audio adds no audio link of its own" do
    both = { video: "/media/video/ep.mp4", audio: "/media/audio/ep.mp3", duration: "00:30:00" }

    get post_path(media_post("podcast", **both).url_name)
    assert_select ".podcast-hero", 1
    assert_select ".podcast-audio-fallback", 0
    assert_no_match "Audio available", response.body

    get post_path(media_post("podcast", **both, content: "#{CARD}\n\nNotes.").url_name)
    assert_select ".podcast-audio-fallback", 0
    assert_no_match "Audio available", response.body
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
    assert Post.new(content: "```card\ntype: player\n```").own_player_card_in_body?
    assert Post.new(content: "Text\n\n  ```card\n  title: A\n  type: \"player\"\n  ```").own_player_card_in_body?
    assert_not Post.new(content: "```card\ntype: pullquote\ntext: type: player\n```").own_player_card_in_body?
    assert_not Post.new(content: "type: player").own_player_card_in_body?
    assert_not Post.new(content: "```collection\ntype: player\n```").own_player_card_in_body?
  end

  # ── a card playing something else ──

  test "a card playing some other file is extra: the post's own player stays" do
    song = "Listen to this:\n\n```card\ntype: player\naudio: /media/audio/song.mp3\n```"

    get post_path(media_post("podcast", audio: "/media/audio/ep.mp3", duration: "00:30:00", content: song).url_name)
    assert_select ".podcast-hero .audio-player", 1
    assert_select ".post-content .card-player audio source[src='/media/audio/song.mp3']", minimum: 1

    get post_path(media_post("audio", audio: "/media/audio/track.mp3", content: song).url_name)
    assert_equal 2, card_players, "the post's track, and the song"

    clip = "```card\ntype: player\nvideo: https://youtu.be/B8A7dGTX8a0\n```"
    get post_path(media_post("video", video: "https://youtu.be/dQw4w9WgXcQ", content: clip).url_name)
    assert_equal 2, iframes
  end

  test "a card naming the post's own file stands in for it, however it's written" do
    post = Post.new(content: "", metadata: { "audio" => "/media/audio/My Show 01.mp3",
                                              "video" => "https://youtu.be/dQw4w9WgXcQ?si=abc" })
    own = ->(src) { post.content = "```card\ntype: player\naudio: #{src}\n```"; post.own_player_card_in_body? }

    assert own.call("/media/audio/My Show 01.mp3")
    assert own.call("\"/media/audio/My Show 01.mp3\"")
    assert own.call("media/audio/My%20Show%2001.mp3")
    assert own.call("/media/audio/My Show 01.mp3?v=2")
    assert own.call("https://example.com/media/audio/My Show 01.mp3")
    assert_not own.call("/media/audio/my show 01.mp3"), "a different name on a case-sensitive server"
    assert_not own.call("/media/audio/song.mp3")

    post.content = "```card\ntype: player\nvideo: https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10\n```"
    assert post.own_player_card_in_body?, "the same YouTube video by another link"
    post.content = "```card\ntype: player\nvideo: https://youtu.be/B8A7dGTX8a0\n```"
    assert_not post.own_player_card_in_body?
  end

  test "one card for the post's own media is enough, even beside another" do
    body = "```card\ntype: player\naudio: /media/audio/song.mp3\n```\n\n```card\ntype: player\n```"
    get post_path(media_post("audio", audio: "/media/audio/track.mp3", content: body).url_name)
    assert_equal 2, card_players, "the card standing in for the post, and the song — no third"
  end
end
