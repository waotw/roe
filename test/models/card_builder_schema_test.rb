# frozen_string_literal: true

require "test_helper"

class CardBuilderSchemaTest < ActiveSupport::TestCase
  # Every key the builder can emit must be one the matching render_<type>
  # method actually reads (see HasMarkdownExtensions). A typo produces a dead
  # option, so guard each type's set.
  SUPPORTED_KEYS = {
    "pullquote"    => %w[text attribution position],
    # link/link_text still render for cards written before link_url existed, but
    # the builder doesn't offer them — see CARD_EXTRA_KEYS.
    "aside"        => %w[text image link_url link link_text],
    "post-link"    => %w[post style title subtitle show_subtitle excerpt show_excerpt url link_text author date image],
    "product-link" => %w[product style title description show_description url link_text image],
    "player"       => %w[audio title image show_artwork]
  }.freeze

  test "types match the renderer's dispatch values" do
    assert_equal %w[pullquote post-link aside product-link player], CardBuilderSchema.types.map { |t| t[:value] }
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

  # Pre-fill used to come from a per-type `button_template`, an invisible second
  # copy of settings cards.yml already had — it carried both `default_style:
  # small` and a template saying `style: small`, with only the first on the
  # settings form. Field `style` now reads `default_style` under that type.
  test "default_values reads that card type's defaults" do
    SiteConfig.stubs(:default).returns(nil)
    SiteConfig.stubs(:default).with("cards", "pullquote").returns({ "default_position" => "right" })

    assert_equal "right", CardBuilderSchema.default_values("pullquote")["position"]
  end

  test "each type reads only its own settings" do
    SiteConfig.stubs(:default).returns(nil)
    SiteConfig.stubs(:default).with("cards", "post-link").returns({ "default_style" => "large" })
    SiteConfig.stubs(:default).with("cards", "pullquote").returns({ "default_position" => "left" })

    assert_equal "large", CardBuilderSchema.default_values("post-link")["style"]
    assert_nil CardBuilderSchema.default_values("pullquote")["style"]
  end

  test "a setting with no matching builder field is ignored" do
    SiteConfig.stubs(:default).returns(nil)
    SiteConfig.stubs(:default).with("cards", "aside").returns({ "default_bogus" => "nope" })

    assert_empty CardBuilderSchema.default_values("aside")
  end

  # A blank setting is "not set" — it must not pre-fill the field with "",
  # which would look configured and write an empty key into the card.
  test "blank and missing settings produce no default" do
    SiteConfig.stubs(:default).returns(nil)
    assert_empty CardBuilderSchema.default_values("pullquote")

    SiteConfig.stubs(:default).with("cards", "pullquote").returns({ "default_position" => "  " })
    assert_empty CardBuilderSchema.default_values("pullquote")
  end
end
