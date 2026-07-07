# frozen_string_literal: true

require "test_helper"

class CardBuilderSchemaTest < ActiveSupport::TestCase
  # Every key the builder can emit must be one the matching render_<type>
  # method actually reads (see HasMarkdownExtensions). A typo produces a dead
  # option, so guard each type's set.
  SUPPORTED_KEYS = {
    "pullquote"    => %w[text attribution position],
    "aside"        => %w[text image link link_text],
    "post-link"    => %w[post style title subtitle show_subtitle excerpt show_excerpt url link_text author date image],
    "product-link" => %w[product style title description show_description url link_text image]
  }.freeze

  test "types match the renderer's dispatch values" do
    assert_equal %w[pullquote post-link aside product-link], CardBuilderSchema.types.map { |t| t[:value] }
  end

  test "every field is well-formed and a real option for its type" do
    CardBuilderSchema.types.each do |t|
      type = t[:value]
      CardBuilderSchema.fields_for(type).each do |field|
        assert field[:key].present?, "#{type} field missing key"
        assert_includes %i[text textarea select boolean post_search product_search], field[:type], "#{type}/#{field[:key]} bad type"
        assert field[:label].present?, "#{type}/#{field[:key]} missing label"
        assert field[:hint].present?, "#{type}/#{field[:key]} missing hint"
        assert field[:options].present?, "#{type}/#{field[:key]} select needs options" if field[:type] == :select
        assert_includes SUPPORTED_KEYS[type], field[:key], "#{type}/#{field[:key]} is not a supported option"
      end
    end
  end

  test "core fields are real fields; only the reference types have them" do
    CardBuilderSchema.types.each do |t|
      type = t[:value]
      keys = CardBuilderSchema.fields_for(type).map { |f| f[:key] }
      CardBuilderSchema.core_for(type).each do |k|
        assert_includes keys, k, "#{type} core field #{k} isn't one of its fields"
      end
    end
    assert_equal %w[post style], CardBuilderSchema.core_for("post-link")
    assert_equal %w[product style], CardBuilderSchema.core_for("product-link")
    assert_empty CardBuilderSchema.core_for("pullquote")
    assert_empty CardBuilderSchema.core_for("aside")
  end

  test "requirements reference real fields of their type" do
    CardBuilderSchema.types.each do |t|
      type = t[:value]
      keys = CardBuilderSchema.fields_for(type).map { |f| f[:key] }
      req = CardBuilderSchema.required_for(type)
      (Array(req[:all]) + Array(req[:any])).each do |k|
        assert_includes keys, k, "#{type} requires #{k}, which isn't one of its fields"
      end
    end
  end

  test "default_values parses a type's button_template, dropping type/placeholder/unknowns" do
    template = "type: pullquote\ntext: __PLACEHOLDER__\nposition: right\nbogus: nope"
    defaults = CardBuilderSchema.default_values("pullquote", template)

    assert_equal "right", defaults["position"]
    assert_nil defaults["text"], "placeholder token should not become a default"
    assert_nil defaults["type"], "type is not a builder field"
    assert_nil defaults["bogus"], "unknown keys should be ignored"
  end

  test "default_values is empty for blank input" do
    assert_empty CardBuilderSchema.default_values("aside", "")
    assert_empty CardBuilderSchema.default_values("aside", nil)
  end
end
