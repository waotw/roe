# frozen_string_literal: true

require "test_helper"

# Roe never rewrites a file under site/ on update, so a setting that moves
# leaves its old key behind. This is what lets the admin explain the leftover
# and remove it on request.
class RetiredConfigSettingsTest < ActiveSupport::TestCase
  def with_config(yaml)
    path = Rails.root.join("tmp", "retired_test.yml")
    File.write(path, yaml)
    yield path
  ensure
    File.delete(path) if File.exist?(path)
  end

  test "it finds the retired keys and leaves everything else alone" do
    config = { "default_limit" => 10, "button_template" => "limit: 5",
               "post_link_button_template" => "style: small" }

    assert_equal %w[button_template post_link_button_template],
      RetiredConfigSettings.in_config(config).keys
  end

  test "a config with none is empty, not an error" do
    assert_empty RetiredConfigSettings.in_config({ "default_limit" => 10 })
    assert_empty RetiredConfigSettings.in_config(nil)
  end

  # The old template's `type:` named the card, which the builder's dropdown does
  # now, and `__PLACEHOLDER__` was a cursor-parking token — neither was a
  # setting, so neither should be offered as one.
  test "type and the placeholder are not settings" do
    parsed = RetiredConfigSettings.parse("type: pullquote\ntext: __PLACEHOLDER__\nposition: right")

    assert_equal [ [ "position", "right" ] ], parsed
  end

  test "it reports what a template line became, and whether it differs" do
    SiteConfig.stubs(:default).returns(nil)
    SiteConfig.stubs(:default).with("collections", "default_limit").returns(10)

    rows = RetiredConfigSettings.replacements_for("collections", "button_template", "limit: 5")

    assert_equal 1, rows.size
    assert_equal({ from: "limit", value: "5", to: "default_limit", current: "10", differs: true }, rows.first)
  end

  test "a matching value is not flagged as differing" do
    SiteConfig.stubs(:default).returns(nil)
    SiteConfig.stubs(:default).with("collections", "default_limit").returns(5)

    assert_not RetiredConfigSettings.replacements_for("collections", "button_template", "limit: 5").first[:differs]
  end

  # cards.yml settings are nested per card type, so the template key is what
  # says which section to look in.
  test "a cards template resolves against its own card type" do
    SiteConfig.stubs(:default).returns(nil)
    SiteConfig.stubs(:default).with("cards", "post-link").returns({ "default_style" => "large" })

    rows = RetiredConfigSettings.replacements_for("cards", "post_link_button_template", "style: small")

    assert_equal "default_style", rows.first[:to]
    assert_equal "large", rows.first[:current]
    assert rows.first[:differs]
  end

  # Nothing to show the user for a line with no equivalent setting — better a
  # shorter table than a row claiming a setting that doesn't exist.
  test "a line with no replacement setting is skipped" do
    SiteConfig.stubs(:default).returns(nil)
    SiteConfig.stubs(:default).with("cards", "aside").returns({})

    assert_empty RetiredConfigSettings.replacements_for("cards", "aside_button_template", "link_url: /x")
  end

  test "strip! removes only the retired keys and reports them" do
    with_config("default_limit: 10\nitems_per_page: 20\nbutton_template: |-\n  limit: 5\n") do |path|
      removed = RetiredConfigSettings.strip!(path)

      assert_equal %w[button_template], removed
      remaining = YAML.safe_load(File.read(path))
      assert_equal({ "default_limit" => 10, "items_per_page" => 20 }, remaining)
    end
  end

  test "strip! on a clean file changes nothing" do
    with_config("default_limit: 10\n") do |path|
      before = File.read(path)

      assert_empty RetiredConfigSettings.strip!(path)
      assert_equal before, File.read(path), "an already-clean file isn't rewritten"
    end
  end

  test "strip! on a missing file is a no-op" do
    assert_empty RetiredConfigSettings.strip!(Rails.root.join("tmp", "nope.yml"))
  end
end
