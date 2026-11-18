require "test_helper"

# What the editor saves has to read back as the same value. A value with lines
# used to be written in double quotes, where YAML folds each line break into a
# space, and a backslash went in unescaped.
class MetadataYamlRoundTripTest < ActiveSupport::TestCase
  def round_trip(value)
    yaml = Post.format_metadata_yaml({ "title" => "T", "pullquote" => value })
    YAML.safe_load(yaml)["pullquote"]
  end

  test "a value with lines keeps them, as a |- block" do
    value = "_the quote_\n— benjamin welch (attribution)"
    yaml = Post.format_metadata_yaml({ "pullquote" => value })

    assert_equal "pullquote: |-\n  _the quote_\n  — benjamin welch (attribution)", yaml
    assert_equal value, round_trip(value)
  end

  test "blank lines, a leading space and Windows line endings survive" do
    assert_equal "one\n\ntwo", round_trip("one\n\ntwo")
    assert_equal "  indented\nnext", round_trip("  indented\nnext")
    assert_equal "a\nb", round_trip("a\r\nb")
  end

  test "lines that look like YAML stay text" do
    value = "key: value\n- item\n# not a comment\n\"quoted\""
    assert_equal value, round_trip(value)
  end

  test "backslashes and quotes on one line read back as written" do
    [ 'C:\new\path', 'say "hi"', 'a \" b', "tab\\t" ].each do |value|
      assert_equal value, round_trip(value), value
    end
  end

  test "a list item with a line break stays in the list" do
    yaml = Post.format_metadata_yaml({ "tags" => [ "a\nb", "c" ] })
    assert_equal [ "a\nb", "c" ], YAML.safe_load(yaml)["tags"]
  end

  test "the next key after a block is still its own key" do
    yaml = Post.format_metadata_yaml({ "pullquote" => "one\ntwo", "title" => "T" })
    assert_equal({ "pullquote" => "one\ntwo", "title" => "T" }, YAML.safe_load(yaml))
  end
end
