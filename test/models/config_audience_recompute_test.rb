# frozen_string_literal: true

require "test_helper"

# A show or release carries an audience its episodes and tracks inherit. Saving
# podcast.yml saves no post, so without a hook here the media index kept the old
# answer until something unrelated happened to be saved — you'd flip a show to
# paid and its MP3s would stay public until you edited an episode.
class ConfigAudienceRecomputeTest < ActiveSupport::TestCase
  AUDIO = "/media/audio/ep.mp3"

  setup do
    absolute = File.join(RoeSitePaths::SITE_PATH, AUDIO.delete_prefix("/"))
    FileUtils.mkdir_p(File.dirname(absolute))
    File.write(absolute, "bytes")
    @medium = Medium.find_or_create_by!(file_path: AUDIO) { |m| m.media_type = "audio" }

    # An episode with no audience of its own — it inherits from its show.
    Post.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "ep.md"),
      content: "Body.",
      metadata: { "title" => "Ep", "url_name" => "ep", "status" => "published",
                  "post_type" => "podcast", "podcast" => "the-show", "audio" => AUDIO }
    )
  end

  teardown do
    path = SiteConfig::FEATURES_PATH.join("podcast.yml")
    File.delete(path) if File.exist?(path)
    SiteConfig.reload!("features/podcast")
  end

  def write_podcast(audience)
    path = SiteConfig::FEATURES_PATH.join("podcast.yml")
    FileUtils.mkdir_p(File.dirname(path))
    entry = PodcastConfig.default_entry.merge("title" => "Show", "audience" => audience)
    File.write(path, { "the-show" => entry }.to_yaml.sub(/\A---\s*\n/, ""))
    SiteConfig.sync_from_file("features/podcast")
  end

  test "flipping a show to paid protects its episodes' files" do
    assert_equal "free", @medium.reload.audience

    write_podcast("paid")

    assert_equal "paid", @medium.reload.audience, "saving podcast.yml should have re-resolved it"
  end

  test "flipping it back releases them" do
    write_podcast("paid")
    assert_equal "paid", @medium.reload.audience

    write_podcast("everyone")

    assert_equal "free", @medium.reload.audience
  end

  # An episode that sets its own audience isn't affected by the show flipping.
  test "an episode's own audience still wins" do
    Post.find_by("json_extract(metadata, '$.url_name') = ?", "ep")
        .update!(metadata: { "title" => "Ep", "url_name" => "ep", "status" => "published",
                             "post_type" => "podcast", "podcast" => "the-show",
                             "audience" => "everyone", "audio" => AUDIO })

    write_podcast("paid")

    assert_equal "free", @medium.reload.audience, "the episode opted out"
  end

  # Configs that carry no audience shouldn't trigger the work at all.
  test "an unrelated config is a no-op" do
    assert_nil Medium.recompute_for_config("site")
    assert_nil Medium.recompute_for_config("defaults/cards")
  end
end
