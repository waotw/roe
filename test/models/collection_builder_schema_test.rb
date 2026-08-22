# frozen_string_literal: true

require "test_helper"

class CollectionBuilderSchemaTest < ActiveSupport::TestCase
  # Every key the builder can emit must be one the collection parser actually
  # reads (see HasMarkdownExtensions#render_collection). A typo here silently
  # produces a dead option, so guard the whole set.
  SUPPORTED_KEYS = %w[
    source heading template style limit order offset post_type podcast release
    show_unlisted tags collection related
    show_author show_excerpt show_date show_subtitle show_more show_more_text
    category groups aspect_ratio show_description
  ].freeze

  test "every field is well-formed" do
    CollectionBuilderSchema.fields.each do |field|
      assert field[:key].present?, "field missing key"
      assert_includes %i[text select boolean], field[:type], "#{field[:key]} has a bad type"
      assert field[:label].present?, "#{field[:key]} missing label"
      assert field[:hint].present?, "#{field[:key]} missing hint"
      if field[:type] == :select
        opts = CollectionBuilderSchema.options_for(field)
        assert opts.is_a?(Array) && opts.any?, "#{field[:key]} select needs options"
      end
    end
  end

  test "all keys are real collection options" do
    CollectionBuilderSchema.fields.each do |field|
      assert_includes SUPPORTED_KEYS, field[:key], "#{field[:key]} is not a supported collection option"
    end
  end

  # The builder has drifted from the renderer before: `music` and the
  # `playlist` template both shipped without being offered here, so a user
  # could build the block by hand but not from the UI.
  test "music post_type and playlist template are offered" do
    post_type = CollectionBuilderSchema.fields.find { |f| f[:key] == "post_type" }
    assert_includes post_type[:options], "music"

    template = CollectionBuilderSchema.fields.find { |f| f[:key] == "template" }
    assert_includes template[:options], "playlist"
  end

  test "playlist gets the feed controls (order, limit, offset)" do
    %w[order limit offset].each do |key|
      field = CollectionBuilderSchema.fields.find do |f|
        f[:key] == key && Array.wrap(f[:depends_on]).any? { |c| c[:in] }
      end
      condition = Array.wrap(field[:depends_on]).find { |c| c[:in] }
      assert_includes condition[:in], "playlist", "#{key} should apply to playlist"
    end
  end

  # Ordered-media sorts are noise on a site that doesn't publish that medium.
  test "numbered sorts are offered only when their feature is enabled" do
    order = CollectionBuilderSchema.fields.find { |f| f[:key] == "order" && f[:type] == :select }

    SiteFeature.stubs(:music_enabled?).returns(false)
    SiteFeature.stubs(:podcast_enabled?).returns(false)
    offered = CollectionBuilderSchema.options_for(order)
    assert_not_includes offered, "track_number"
    assert_not_includes offered, "episode_number"
    assert_includes offered, "date", "the base sorts are always offered"

    SiteFeature.stubs(:music_enabled?).returns(true)
    SiteFeature.stubs(:podcast_enabled?).returns(true)
    offered = CollectionBuilderSchema.options_for(order)
    assert_includes offered, "track_number"
    assert_includes offered, "episode_number"
  end

  # Every offered sort must be one the query actually understands.
  test "offered order options are all real sort keywords" do
    SiteFeature.stubs(:music_enabled?).returns(true)
    SiteFeature.stubs(:podcast_enabled?).returns(true)
    order = CollectionBuilderSchema.fields.find { |f| f[:key] == "order" && f[:type] == :select }

    CollectionBuilderSchema.options_for(order).each do |opt|
      assert CollectionQuery.sort_keyword?(opt), "`#{opt}` is offered but isn't a sort keyword"
    end
  end

  test "depends_on conditions reference existing fields" do
    keys = CollectionBuilderSchema.fields.map { |f| f[:key] }
    CollectionBuilderSchema.fields.each do |field|
      Array.wrap(field[:depends_on]).each do |cond|
        assert_includes keys, cond[:field], "#{field[:key]} depends on unknown field #{cond[:field]}"
      end
    end
  end

  # The builder used to pre-fill from a `button_template` — a second copy of
  # these same settings that wasn't on the settings form. It had drifted:
  # `limit: 5` in the template against `default_limit: 10` in the settings, so
  # a built collection and a hand-written one disagreed. One source now.
  test "default_values reads the site's collection defaults" do
    SiteConfig.stubs(:default).returns(nil)
    SiteConfig.stubs(:default).with("collections", "default_limit").returns(10)
    SiteConfig.stubs(:default).with("collections", "default_template").returns("grid")

    defaults = CollectionBuilderSchema.default_values

    assert_equal "10", defaults["limit"]
    assert_equal "grid", defaults["template"]
  end

  test "a setting that isn't a builder field is ignored" do
    SiteConfig.stubs(:default).returns(nil)
    SiteConfig.stubs(:default).with("collections", "default_bogus").returns("nope")

    assert_empty CollectionBuilderSchema.default_values
  end

  # A blank setting is "not set" — it must not pre-fill the field with "",
  # which would look configured and write an empty key into the block.
  test "blank and missing settings produce no default" do
    SiteConfig.stubs(:default).returns(nil)
    assert_empty CollectionBuilderSchema.default_values

    SiteConfig.stubs(:default).with("collections", "default_limit").returns("   ")
    assert_empty CollectionBuilderSchema.default_values
  end
end
