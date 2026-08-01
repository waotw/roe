# frozen_string_literal: true

require "test_helper"

class ActionBuilderSchemaTest < ActiveSupport::TestCase
  # Every key the builder can emit must be one the matching renderer actually
  # reads (see HasMarkdownExtensions: render_share_button, render_members_button,
  # render_form's per-`for` branches, ProductButtonRenderer). A typo produces a
  # dead option, so guard each kind's set.
  SUPPORTED_KEYS = {
    "product"      => %w[sku text style quantity show_price],
    "share"        => %w[label url title text style],
    "subscribe"    => %w[label url style],
    "signup"       => %w[button-text upgrade-button-text],
    "signin"       => %w[button-text],
    "checkout"     => %w[member-button-text non-member-button-text],
    "donate"       => %w[button-text],
    "unsubscribe"  => %w[button-text],
    "paid_content" => %w[text button-text]
  }.freeze

  test "button kinds are feature-gated; share is always available" do
    assert_equal %w[product share subscribe],
                 ActionBuilderSchema.button_kinds(store: true, members: true).map { |k| k[:value] }
    assert_equal %w[product share],
                 ActionBuilderSchema.button_kinds(store: true, members: false).map { |k| k[:value] }
    assert_equal %w[share subscribe],
                 ActionBuilderSchema.button_kinds(store: false, members: true).map { |k| k[:value] }
    assert_equal %w[share],
                 ActionBuilderSchema.button_kinds(store: false, members: false).map { |k| k[:value] }
  end

  test "form kinds require members; the paywall (paid_content) requires payments" do
    assert_equal %w[signup signin checkout donate unsubscribe paid_content],
                 ActionBuilderSchema.form_kinds(members: true, payments: true).map { |k| k[:value] }
    # Members on, payments off → everything but the paywall.
    assert_equal %w[signup signin checkout donate unsubscribe],
                 ActionBuilderSchema.form_kinds(members: true, payments: false).map { |k| k[:value] }
    assert_empty ActionBuilderSchema.form_kinds(members: false, payments: false)
  end

  test "every field is well-formed and a real option for its kind" do
    all_kinds = ActionBuilderSchema::BUTTON_KINDS + ActionBuilderSchema::FORM_KINDS
    all_kinds.each do |k|
      kind = k[:value]
      fields = ActionBuilderSchema.fields_for(kind)
      assert fields.any?, "#{kind} has no fields"
      fields.each do |field|
        assert field[:key].present?, "#{kind} field missing key"
        assert_includes %i[text textarea select], field[:type], "#{kind}/#{field[:key]} bad type"
        assert field[:label].present?, "#{kind}/#{field[:key]} missing label"
        assert field[:hint].present?, "#{kind}/#{field[:key]} missing hint"
        assert field[:options].present?, "#{kind}/#{field[:key]} select needs options" if field[:type] == :select
        assert_includes SUPPORTED_KEYS[kind], field[:key], "#{kind}/#{field[:key]} is not a key its renderer reads"
      end
    end
  end

  test "kind labels and values are present and unique across blocks" do
    all_kinds = ActionBuilderSchema::BUTTON_KINDS + ActionBuilderSchema::FORM_KINDS
    values = all_kinds.map { |k| k[:value] }
    assert_equal values.uniq, values, "kind values must be globally unique (groups are keyed by kind alone)"
    all_kinds.each { |k| assert k[:label].present?, "#{k[:value]} missing label" }
  end

  test "fields_for is empty for an unknown kind" do
    assert_empty ActionBuilderSchema.fields_for("nope")
  end
end
