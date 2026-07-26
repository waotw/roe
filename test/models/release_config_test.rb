require "test_helper"

class ReleaseConfigTest < ActiveSupport::TestCase
  def stub_music(hash)
    SiteConfig.stubs(:current).with("features/music").returns(stub(config: hash))
  end

  test "release_keys lists the entries under releases:" do
    stub_music({ "artist" => "Me", "releases" => { "summer" => {}, "winter" => {} } })
    assert_equal %w[summer winter], ReleaseConfig.release_keys
  end

  test "get returns a release, nil for a missing key" do
    stub_music({ "releases" => { "summer" => { "title" => "Summer" } } })
    assert_equal({ "title" => "Summer" }, ReleaseConfig.get("summer"))
    assert_nil ReleaseConfig.get("missing")
  end

  test "audience resolves release override, then global, then free" do
    stub_music({ "audience" => "paid", "releases" => { "a" => {}, "b" => { "audience" => "free" } } })
    assert_equal "paid", ReleaseConfig.audience_for("a"), "inherits the global"
    assert_equal "free", ReleaseConfig.audience_for("b"), "release overrides"
    assert ReleaseConfig.paid?("a")
    assert_not ReleaseConfig.paid?("b")
  end

  test "audience_for falls back to free when nothing is set" do
    stub_music({ "releases" => { "a" => {} } })
    assert_equal "free", ReleaseConfig.audience_for("a")
  end

  test "artist resolves release override, then global, then site author" do
    stub_music({ "artist" => "Global", "releases" => { "a" => {}, "b" => { "artist" => "Guest" } } })
    assert_equal "Global", ReleaseConfig.artist_for("a")
    assert_equal "Guest", ReleaseConfig.artist_for("b")
  end

  test "artist falls back to the site author when music.yml has no artist" do
    stub_music({ "releases" => { "a" => {} } })
    SiteConfig.stubs(:get).with("author_name").returns("Site Author")
    assert_equal "Site Author", ReleaseConfig.artist_for("a")
  end

  test "an absent music.yml means no releases, not an error" do
    SiteConfig.stubs(:current).with("features/music").returns(nil)
    assert_equal({}, ReleaseConfig.all_releases)
    assert_empty ReleaseConfig.release_keys
  end
end
