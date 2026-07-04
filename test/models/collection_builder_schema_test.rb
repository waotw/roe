# frozen_string_literal: true

require "test_helper"

class CollectionBuilderSchemaTest < ActiveSupport::TestCase
  # Every key the builder can emit must be one the collection parser actually
  # reads (see HasMarkdownExtensions#render_collection). A typo here silently
  # produces a dead option, so guard the whole set.
  SUPPORTED_KEYS = %w[
    source heading template limit order offset post_type podcast tags related
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
        assert field[:options].present?, "#{field[:key]} select needs options"
      end
    end
  end

  test "all keys are real collection options" do
    CollectionBuilderSchema.fields.each do |field|
      assert_includes SUPPORTED_KEYS, field[:key], "#{field[:key]} is not a supported collection option"
    end
  end

  test "depends_on references an existing field" do
    keys = CollectionBuilderSchema.fields.map { |f| f[:key] }
    CollectionBuilderSchema.fields.each do |field|
      dep = field[:depends_on]
      next unless dep

      assert_includes keys, dep[:field], "#{field[:key]} depends on unknown field #{dep[:field]}"
    end
  end

  test "default_values parses a button_template, dropping unknowns and the placeholder" do
    template = "heading: __PLACEHOLDER__\nlimit: 5\ntemplate: list\nbogus: nope"
    defaults = CollectionBuilderSchema.default_values(template)

    assert_equal "5", defaults["limit"]
    assert_equal "list", defaults["template"]
    assert_nil defaults["heading"], "placeholder token should not become a default"
    assert_nil defaults["bogus"], "unknown keys should be ignored"
  end

  test "default_values is empty for blank input" do
    assert_empty CollectionBuilderSchema.default_values("")
    assert_empty CollectionBuilderSchema.default_values(nil)
  end
end
