# frozen_string_literal: true

require "test_helper"

# MarkdownDoctor finds formatting problems Kramdown handles differently from
# how the author meant, and fixes only the ones with a single correct rewrite.
#
# It takes content rather than a path because the editor lints the textarea,
# which hasn't been saved yet.
class MarkdownDoctorTest < ActiveSupport::TestCase
  def types(content)
    MarkdownDoctor.diagnose(content).map { |i| i[:type] }
  end

  # --- detection -----------------------------------------------------------

  test "clean markdown reports nothing" do
    assert_empty MarkdownDoctor.diagnose("# Title\n\nA paragraph.\n\n- one\n- two\n")
  end

  test "a list item without a blank line above it is flagged" do
    issues = MarkdownDoctor.diagnose("Intro paragraph\n- an item\n")

    assert_equal [ :list_spacing ], issues.map { |i| i[:type] }
    assert_equal 2, issues.first[:line]
  end

  test "front matter is skipped, and line numbers still point at the file" do
    content = "---\ntitle: \"X\"\n---\nIntro\n- an item\n"
    issues = MarkdownDoctor.diagnose(content)

    assert_equal [ :list_spacing ], issues.map { |i| i[:type] }
    assert_equal 5, issues.first[:line], "line number counts from the top of the file"
  end

  test "list-like lines inside a code block are left alone" do
    content = "Intro\n\n```\nsome text\n- not a list\n```\n"

    assert_empty MarkdownDoctor.diagnose(content)
  end

  test "a nested list item needs no blank line" do
    assert_empty MarkdownDoctor.diagnose("- parent\n    - child\n")
  end

  test "fence problems are detected" do
    assert_includes types("``\ncode\n``\n"), :invalid_fence_length
    assert_includes types("```ruby\ncode\n"), :unclosed_fence
  end

  # --- what Fix All may touch ----------------------------------------------

  # Every issue carries this, so the UI can say what it will and won't change.
  test "issues are marked fixable or not" do
    spacing = MarkdownDoctor.diagnose("Intro\n- item\n").first
    unclosed = MarkdownDoctor.diagnose("```ruby\ncode\n").first

    assert spacing[:fixable]
    assert_not unclosed[:fixable]
  end

  # An unclosed fence has no knowable closing point; guessing swallows the rest
  # of the document into a code block. A mismatched closer is ambiguous in a
  # different way — the opener or the closer could be the mistake.
  test "fence issues are never auto-fixed" do
    %i[invalid_fence_length mismatched_fence nested_same_length_fence
       four_fence_without_nesting unclosed_fence].each do |type|
      assert_not MarkdownDoctor.fixable?(type), "#{type} must stay a warning"
    end
  end

  # --- fixing --------------------------------------------------------------

  test "fix inserts the missing blank line and leaves the prose alone" do
    fixed, applied = MarkdownDoctor.fix("Intro paragraph\n- an item\n")

    assert_equal "Intro paragraph\n\n- an item\n", fixed
    assert_equal [ :list_spacing ], applied.map { |i| i[:type] }
  end

  test "fix indents a blockquote that would break out of a list" do
    content = "- first item\n> a quote\n- second item\n"
    fixed, applied = MarkdownDoctor.fix(content)

    # This content trips two rules at once — the escaping blockquote and the
    # list item that follows it without a blank line. Both are fixable.
    assert_includes applied.map { |i| i[:type] }, :unindented_blockquote_in_list
    assert_includes fixed, "    > a quote", "four spaces keeps it inside the item"
    assert_empty MarkdownDoctor.diagnose(fixed)
  end

  # Fixes are applied back to front so earlier line numbers stay valid.
  test "several fixes in one pass all land in the right place" do
    fixed, applied = MarkdownDoctor.fix("Intro\n- one\n\nMore prose\n- two\n")

    assert_equal 2, applied.size
    assert_empty MarkdownDoctor.diagnose(fixed), "the result should be clean"
  end

  test "fixing is idempotent" do
    once, = MarkdownDoctor.fix("Intro\n- item\n")
    twice, applied = MarkdownDoctor.fix(once)

    assert_equal once, twice
    assert_empty applied
  end

  test "clean content is returned untouched" do
    content = "# Title\n\nA paragraph.\n\n- one\n"
    fixed, applied = MarkdownDoctor.fix(content)

    assert_equal content, fixed
    assert_empty applied
  end

  # The whole point of excluding them: content must survive Fix All intact.
  test "fix leaves unfixable issues exactly as written" do
    content = "```ruby\nputs 1\n"
    fixed, applied = MarkdownDoctor.fix(content)

    assert_equal content, fixed, "an unclosed fence must not be guessed at"
    assert_empty applied
  end
end
