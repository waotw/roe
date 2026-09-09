require "test_helper"

# post_type_options drives the editor's type picker. Feature-gated types
# (podcast, music) only appear when their feature is on — unless a post already
# uses the type, in which case it stays visible so it never vanishes.
class PostTypeOptionsTest < ActiveSupport::TestCase
  setup { Rails.cache.delete("post_type_options/v2") }
  teardown { Rails.cache.delete("post_type_options/v2") }

  # POST_TYPES declaration order IS the picker order, so reordering that hash is
  # all it takes to reorder the picker.
  test "options follow POST_TYPES declaration order" do
    SiteFeature.stubs(:podcast_enabled?).returns(true)
    SiteFeature.stubs(:music_enabled?).returns(true)
    Post.stubs(:all_post_types).returns([])

    assert_equal %w[article podcast music audio video], Post.post_type_options
  end

  test "legacy types in use follow the known ones, alphabetically" do
    SiteFeature.stubs(:podcast_enabled?).returns(true)
    SiteFeature.stubs(:music_enabled?).returns(true)
    Post.stubs(:all_post_types).returns(%w[zine essay])

    assert_equal %w[article podcast music audio video essay zine], Post.post_type_options
  end

  # The gate is derived from each type's `feature:` key, so a type is defined in
  # one place only.
  test "FEATURE_GATED_TYPES is derived from POST_TYPES" do
    assert_equal({ "podcast" => :podcast_enabled?, "music" => :music_enabled? },
                 Post::FEATURE_GATED_TYPES)
    Post::POST_TYPES.each do |type, config|
      next unless config[:feature]
      assert_equal config[:feature], Post::FEATURE_GATED_TYPES[type.to_s]
    end
  end

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
