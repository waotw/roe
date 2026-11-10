require "test_helper"

class ContentMetadataSchemaPageSeriesTest < ActiveSupport::TestCase
  test "pages offer podcast and release when those features are on" do
    SiteFeature.stubs(:podcast_enabled?).returns(true)
    SiteFeature.stubs(:music_enabled?).returns(true)
    PodcastConfig.stubs(:podcast_keys).returns(%w[show])
    ReleaseConfig.stubs(:release_keys).returns(%w[summer-ep])

    fields = ContentMetadataSchema.fields_for("page")
    assert_includes fields["podcast"][:options], "show"
    assert_includes fields["release"][:options], "summer-ep"
    assert_equal %w[subtitle podcast release], ContentMetadataSchema.create_fields_for("page").map { |f| f[:name] }
  end

  test "with the features off they aren't offered, but a value already set still shows" do
    SiteFeature.stubs(:podcast_enabled?).returns(false)
    SiteFeature.stubs(:music_enabled?).returns(false)
    PodcastConfig.stubs(:podcast_keys).returns([])
    ReleaseConfig.stubs(:release_keys).returns([])

    assert_equal %w[subtitle], ContentMetadataSchema.create_fields_for("page").map { |f| f[:name] }
    fields = ContentMetadataSchema.fields_for("page", metadata: { "release" => "old-ep" })
    assert_equal false, fields["release"][:available]
    assert_includes fields["release"][:options], "old-ep", "saving must not clear it"
  end

  test "a page made for a release or podcast gets no # title in its body" do
    assert_not_includes ContentScaffold.body_for("page", metadata: { "title" => "EP", "release" => "summer-ep" }), "# EP"
    assert_not_includes ContentScaffold.body_for("page", metadata: { "title" => "Show", "podcast" => "show" }), "# Show"
    assert_includes ContentScaffold.body_for("page", metadata: { "title" => "About" }), "# About"
  end
end
