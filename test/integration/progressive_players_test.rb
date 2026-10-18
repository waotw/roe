require "test_helper"

# Every player is progressive: it plays in the browser's own controls as
# rendered, and site_js/player.js swaps in Roe's. So a static export, or a
# page whose script never loads, still plays — the same markup on both.
class ProgressivePlayersTest < ActionDispatch::IntegrationTest
  def media_post(type, content: "Words.", **fields)
    @n = (@n || 0) + 1
    create(:post,
      metadata: { "title" => "#{type} #{@n}", "status" => "published", "date" => "2024-01-01",
                  "audience" => "everyone", "post_type" => type }.merge(fields.transform_keys(&:to_s)),
      content: content)
  end

  # What a visitor without the script gets: each player's media element
  # shows its browser controls, and Roe's controls are hidden.
  def assert_plays_without_script(selector)
    root = css_select(selector).first
    assert root, "#{selector} is on the page"
    media = root.at_css("[data-player-part=media]")
    assert media, "#{selector} has its media element"
    assert media.key?("controls"), "#{selector}: the browser's controls show"
    assert_not media.key?("hidden"), "#{selector}: and the element isn't hidden"
    root.css("[data-player-ui]").each do |ui|
      assert ui.key?("hidden"), "#{selector}: Roe's controls wait for player.js"
    end
  end

  test "the player card plays without the script" do
    get post_path(media_post("audio", audio: "/media/audio/track.mp3").url_name)
    assert_plays_without_script ".card-player[data-player=audio]"
    assert_select ".card-player audio source[src='/media/audio/track.mp3']", minimum: 1
  end

  test "the podcast player plays without the script, chapters readable" do
    chapters = [ { "time" => 0, "title" => "Intro" }, { "time" => 75, "title" => "The Journal" }, { "time" => 3723, "title" => "Late" } ]
    get post_path(media_post("podcast", audio: "/media/audio/ep.mp3", duration: "01:10:00", chapters: chapters).url_name)

    assert_plays_without_script ".podcast-hero .audio-player[data-player=audio]"
    assert_select ".chapter-list [data-player-chapter]", 3
    assert_select ".chapter[data-time='75.0'] .chapter-time", "1:15"
    assert_select ".chapter[data-time='3723.0'] .chapter-time", "1:02:03"
    assert_select ".chapter .chapter-title", "The Journal"
  end

  test "a video plays without the script" do
    get post_path(media_post("video", video: "/media/video/clip.mp4").url_name)
    assert_plays_without_script ".video-player-container[data-player=video]"
  end

  test "the layout loads player.js like the other site scripts, and no Stimulus wiring is left" do
    get post_path(media_post("audio", audio: "/media/audio/track.mp3").url_name)

    assert_select "script[src='/javascript/player.js'][defer]"
    assert_no_match(/audio-player#|data-audio-player|data-controller="audio-player"/, response.body)
  end

  test "player.js ships as a site script, so it's seeded into site/javascript and updatable" do
    assert_includes SiteJavascript.shipped_names, "player.js"
    header = ShippedFileInspector.parse_header(File.join(SiteJavascript.source_dir, "player.js"))
    assert header, "it has a Roe Script header"
    assert_equal "player", header.name
  end

  test "the static export writes the same progressive player" do
    post = media_post("audio", audio: "/media/audio/track.mp3")
    out = Rails.root.join("tmp", "progressive_static_#{SecureRandom.hex(4)}")
    StaticGenerator.new(output_dir: out).send(:generate_post, post)
    doc = Nokogiri::HTML(File.read(out.join("posts", "#{post.url_name}.html")))

    media = doc.at_css(".card-player [data-player-part=media]")
    assert media&.key?("controls"), "a static visitor gets a working audio bar"
    assert doc.at_css("script[src$='javascript/player.js']"), "and player.js to upgrade it"
  ensure
    FileUtils.rm_rf(out) if out
  end
end
