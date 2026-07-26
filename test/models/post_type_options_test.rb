require "test_helper"

# post_type_options drives the editor's type picker. Feature-gated types
# (podcast, music) only appear when their feature is on — unless a post already
# uses the type, in which case it stays visible so it never vanishes.
class PostTypeOptionsTest < ActiveSupport::TestCase
  setup { Rails.cache.delete("post_type_options") }
  teardown { Rails.cache.delete("post_type_options") }

  test "a feature-gated type is hidden when its feature is off" do
    SiteFeature.stubs(:music_enabled?).returns(false)
    Post.stubs(:all_post_types).returns([])

    assert_not_includes Post.post_type_options, "music"
    assert_includes Post.post_type_options, "article", "ungated types are unaffected"
  end

  test "a feature-gated type appears when its feature is on" do
    SiteFeature.stubs(:music_enabled?).returns(true)
    Post.stubs(:all_post_types).returns([])

    assert_includes Post.post_type_options, "music"
  end

  test "a gated type already in use stays visible even with the feature off" do
    SiteFeature.stubs(:music_enabled?).returns(false)
    Post.stubs(:all_post_types).returns([ "music" ])

    assert_includes Post.post_type_options, "music"
  end
end
