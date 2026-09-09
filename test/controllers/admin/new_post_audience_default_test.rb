# frozen_string_literal: true

require "test_helper"

# The new-post form's audience select defaults to `everyone`, which was right
# before shows and releases carried an audience. Now clicking past that field
# on a paid podcast creates a public episode — a mistake you'd notice when
# someone got it for free. The form hands the controller the paid keys so it
# can default to match the container.
class Admin::NewPostAudienceDefaultTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    SiteFeature.stubs(:members_enabled?).returns(true)
  end

  teardown do
    path = SiteConfig::FEATURES_PATH.join("podcast.yml")
    File.delete(path) if File.exist?(path)
    SiteConfig.reload!("features/podcast")
  end

  def write_shows(shows)
    path = SiteConfig::FEATURES_PATH.join("podcast.yml")
    FileUtils.mkdir_p(File.dirname(path))
    entries = shows.transform_values do |audience|
      PodcastConfig.default_entry.merge("title" => "Show", "audience" => audience)
    end
    File.write(path, entries.to_yaml.sub(/\A---\s*\n/, ""))
    SiteConfig.sync_from_file("features/podcast")
  end

  test "the form carries the paid shows so the default can follow them" do
    write_shows("paid-show" => "paid", "free-show" => "everyone")

    get new_admin_post_path

    assert_response :success
    assert_select "[data-audience-default-paid-podcasts-value]" do |el|
      keys = JSON.parse(el.first["data-audience-default-paid-podcasts-value"])
      assert_equal [ "paid-show" ], keys
    end
  end

  test "the audience select is wired to the controller" do
    write_shows("paid-show" => "paid")

    get new_admin_post_path

    assert_select "select[name=?][data-audience-default-target=?]", "fields[audience]", "audience"
    assert_select "select[name=?][data-action*=?]", "fields[audience]", "audience-default#userChose"
  end

  # With nothing paid there's nothing to flip to, and the list stays empty
  # rather than the controller guessing.
  test "no paid shows means an empty list" do
    write_shows("free-show" => "everyone")

    get new_admin_post_path

    assert_select "[data-audience-default-paid-podcasts-value=?]", "[]"
  end

  test "the controller is absent when members are off" do
    SiteFeature.stubs(:members_enabled?).returns(false)

    get new_admin_post_path

    assert_select "form[data-controller=?]", "new-content"
  end
end
