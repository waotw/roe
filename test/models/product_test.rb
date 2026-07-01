require "test_helper"

class ProductTest < ActiveSupport::TestCase
  # primary is an ordinary optional field — only an explicit true counts.
  test "primary? is true only for an explicit true (bool or string)" do
    assert Product.new(metadata: { "primary" => true }).primary?
    assert Product.new(metadata: { "primary" => "true" }).primary?
  end

  test "primary? reads a missing, blank, or false value as false" do
    refute Product.new(metadata: {}).primary?
    refute Product.new(metadata: { "primary" => "" }).primary?
    refute Product.new(metadata: { "primary" => false }).primary?
    refute Product.new(metadata: { "primary" => "false" }).primary?
  end

  # A group is defined by the group name alone; the other fields are optional
  # and a lone grouped product (not yet a 2+ group) raises no warnings.
  test "a product with only a group is valid and unflagged" do
    p = Product.new(metadata: { "title" => "Solo", "status" => "draft", "group" => "boots" })
    assert_empty p.group_issues
    refute p.flagged?
  end
end
