# frozen_string_literal: true

require "test_helper"

# A post-link's subtitle and excerpt default by style — off for small, on for
# medium and large (excerpt: large only). A site that wants one of them on
# everywhere had no way to say so short of editing every card.
#
# Three levels now, narrowest first: the card's own `show_subtitle:` wins over
# everything, a cards.yml setting fixes the default for all styles, and with
# neither the style decides — which is what every existing install has.
class CardStyleDefaultTest < ActiveSupport::TestCase
  class TestModel
    include HasMarkdownExtensions
    include HasInlineFootnotes
    attr_accessor :content
    def initialize(content) = @content = content
  end

  # by_style is what the renderer passes: the rule that applies when nothing
  # has overridden it.
  def resolved(key, by_style, setting: :none)
    stub_cards(setting == :none ? {} : { "default_#{key}" => setting })
    TestModel.new("").send(:card_style_default, "post-link", key, by_style)
  end

  def label(setting: :none)
    stub_cards(setting == :none ? {} : { "default_show_subtitle" => setting })
    CardBuilderSchema.default_label("post-link", "show_subtitle")
  end

  # The setting reaches the renderer through SiteConfig, which reads the
  # database rather than cards.yml directly — so the section is stubbed instead
  # of the file being written.
  def stub_cards(section)
    SiteConfig.stubs(:default).returns(section)
  end

  test "with no setting, the style decides" do
    assert_not resolved("show_subtitle", false), "small"
    assert resolved("show_subtitle", true), "medium and large"
    assert resolved("show_excerpt", true), "large"
    assert_not resolved("show_excerpt", false), "small and medium"
  end

  test "a setting fixes the default for every style" do
    assert resolved("show_subtitle", false, setting: "true"), "small, which the style rule turns off"
    assert resolved("show_subtitle", true, setting: "true")

    assert_not resolved("show_subtitle", true, setting: "false"), "medium, which the style rule turns on"
    assert_not resolved("show_subtitle", false, setting: "false")
  end

  test "excerpt has its own setting" do
    assert resolved("show_excerpt", false, setting: "true")
    assert_not resolved("show_excerpt", true, setting: "false")
  end

  # The config editor writes an empty string for a field nobody filled in, so
  # blank has to mean the same as absent or saving the file would silently turn
  # every subtitle off.
  test "a blank setting is no setting" do
    assert_not resolved("show_subtitle", false, setting: "")
    assert resolved("show_subtitle", true, setting: "   ")
  end

  test "true and false are read whatever their case or type" do
    assert resolved("show_subtitle", false, setting: "TRUE")
    assert resolved("show_subtitle", false, setting: true)
    assert_not resolved("show_subtitle", true, setting: false)
  end

  # Only these two are style-dependent; nothing else should start reading
  # settings that don't exist.
  test "a key with no setting behind it is untouched" do
    assert resolved("show_author", true, setting: "false"), "no default_show_author exists"
  end

  # The builder's "—" option leaves the key out of the card, which is what lets
  # the card follow the setting later. The label says what that will do.
  test "the builder says what leaving it unset will do" do
    assert_equal "default: by style", label
    assert_equal "default: on", label(setting: "true")
    assert_equal "default: off", label(setting: "false")
    assert_equal "default: by style", label(setting: ""), "blank is no setting"
  end

  test "a boolean with no style rule just says default" do
    stub_cards({})

    assert_equal "default", CardBuilderSchema.default_label("post-link", "show_artwork")
  end
end
