# frozen_string_literal: true

require "test_helper"

# Content → Global → "Automatically add audio and video duration".
#
# On: Roe sets a post's duration to its file's length on every save — but
# only a length it could confirm. No file, a missing file, or one it can't
# read leaves whatever is there, so a writer can still type one in.
# Off: the duration is the writer's; the field gets ADD DURATION instead.
class Admin::AutoDurationTest < ActionDispatch::IntegrationTest
  AUDIO_DIR = File.join(RoeSitePaths::SITE_PATH, "media", "audio", "auto_duration_test").freeze

  # A real WAV of the given length: silence, 8 kHz, 8-bit mono. WahWah reads
  # its length from the header, so no ffmpeg is needed.
  def self.wav(seconds)
    rate = 8000
    data = "\x80".b * (rate * seconds)
    [ "RIFF", 36 + data.bytesize, "WAVE", "fmt ", 16, 1, 1, rate, rate, 1, 8, "data", data.bytesize ]
      .pack("a4Va4a4VvvVVvva4V") + data
  end

  setup do
    sign_in_as(create(:user))
    FileUtils.mkdir_p(AUDIO_DIR)
    File.binwrite(File.join(AUDIO_DIR, "ninety.wav"), self.class.wav(90))
    File.binwrite(File.join(AUDIO_DIR, "broken.mp3"), "not audio at all")

    @post = create(:post, metadata: { "title" => "Episode", "post_type" => "audio", "status" => "draft" })
    FileUtils.mkdir_p(File.dirname(@post.file_path))
    File.write(@post.file_path, "---\ntitle: Episode\npost_type: audio\nstatus: draft\n---\nBody.\n")
  end

  teardown do
    FileUtils.rm_rf(AUDIO_DIR)
    FileUtils.rm_f(@post.file_path)
    FileUtils.rm_f(SiteConfig::CONTENT_FILE)
  end

  def auto_duration(on)
    FileUtils.mkdir_p(File.dirname(SiteConfig::CONTENT_FILE))
    File.write(SiteConfig::CONTENT_FILE, "auto_duration: #{on}\n")
  end

  def save(metadata)
    patch admin_post_path(@post), params: { metadata: metadata.to_yaml.sub(/\A---\n/, ""), content: "Body." }
    assert_redirected_to edit_admin_post_path(@post)
    FrontMatterParser::Parser.new(:md).call(File.read(@post.file_path)).front_matter
  end

  def episode(extra = {})
    { "title" => "Episode", "post_type" => "audio", "status" => "draft" }.merge(extra)
  end

  test "the length is read from the file itself" do
    assert_equal "00:01:30", MediaDurationExtractor.for_media("/media/audio/auto_duration_test/ninety.wav")
    assert_nil MediaDurationExtractor.for_media("/media/audio/auto_duration_test/broken.mp3")
    assert_nil MediaDurationExtractor.for_media("/media/audio/auto_duration_test/gone.mp3")
    assert_nil MediaDurationExtractor.for_media("/media/../config/master.key")
    assert_nil MediaDurationExtractor.for_media("https://cdn.example.com/elsewhere.mp3")
    assert_nil MediaDurationExtractor.for_media("")
  end

  test "a YouTube link's length comes from YouTube" do
    VideoEmbed.any_instance.stubs(:duration_seconds).returns(213)
    assert_equal "00:03:33", MediaDurationExtractor.for_media("https://youtu.be/dQw4w9WgXcQ")

    VideoEmbed.any_instance.stubs(:duration_seconds).returns(nil)
    assert_nil MediaDurationExtractor.for_media("https://youtu.be/dQw4w9WgXcQ")
  end

  test "on by default: a save sets the duration to the file's, over what was typed" do
    saved = save(episode("audio" => "/media/audio/auto_duration_test/ninety.wav", "duration" => "00:00:05"))
    assert_equal "00:01:30", saved["duration"]

    # No duration yet: added.
    saved = save(episode("audio" => "/media/audio/auto_duration_test/ninety.wav"))
    assert_equal "00:01:30", saved["duration"]
  end

  test "on, but the length can't be confirmed: what's there is kept" do
    %w[/media/audio/auto_duration_test/gone.mp3
       /media/audio/auto_duration_test/broken.mp3
       https://cdn.example.com/elsewhere.mp3].each do |source|
      saved = save(episode("audio" => source, "duration" => "00:42:00"))
      assert_equal "00:42:00", saved["duration"], "replaced the typed length for #{source}"
    end

    # No file at all: nothing to do.
    saved = save(episode("duration" => "00:42:00"))
    assert_equal "00:42:00", saved["duration"]
    saved = save(episode)
    assert_nil saved["duration"]
  end

  test "audio comes first: it's what the feed sends" do
    File.binwrite(File.join(AUDIO_DIR, "sixty.wav"), self.class.wav(60))
    saved = save(episode("post_type" => "podcast",
                         "audio" => "/media/audio/auto_duration_test/sixty.wav",
                         "video" => "/media/audio/auto_duration_test/ninety.wav"))
    assert_equal "00:01:00", saved["duration"]
  end

  test "a post type without a duration doesn't get one" do
    saved = save(episode("post_type" => "article", "video" => "/media/audio/auto_duration_test/ninety.wav"))
    assert_not saved.key?("duration")
  end

  test "off: the duration is left exactly as written" do
    auto_duration(false)

    saved = save(episode("audio" => "/media/audio/auto_duration_test/ninety.wav", "duration" => "00:00:05"))
    assert_equal "00:00:05", saved["duration"]

    saved = save(episode("audio" => "/media/audio/auto_duration_test/ninety.wav"))
    assert_nil saved["duration"]
  end

  test "the setting sits under Content → Global, above Writing editor, ticked when unset" do
    get admin_edit_content_config_path
    assert_response :success

    body = response.body
    label = body.index("Automatically add audio and video duration")
    assert label, "setting missing"
    assert_operator label, :<, body.index("Writing editor")
    assert_includes body, "Let Roe handle the duration settings for audio and video files"
    assert_select "input[type=checkbox][data-config-field=auto_duration][checked]"
  end

  test "the editor's duration field can be typed in, and says who fills it" do
    File.write(@post.file_path, "---\ntitle: Episode\npost_type: audio\nstatus: draft\naudio: /media/audio/auto_duration_test/ninety.wav\nduration: \"00:01:30\"\n---\nBody.\n")
    ContentSync.sync_file(@post.file_path)

    get edit_admin_post_path(@post)
    assert_select "meta[name=roe-auto-duration][content=on]"
    assert_select "[data-controller~=duration-detect]"
    assert_select "input[data-metadata-field=duration]:not([readonly])[placeholder=?]", "Set from the file on save"

    auto_duration(false)
    get edit_admin_post_path(@post)
    assert_select "meta[name=roe-auto-duration][content=off]"
    assert_select "input[data-metadata-field=duration]:not([readonly])[placeholder=?]", "HH:MM:SS"
  end
end
