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

  # The mirror of list spacing. Kramdown renders this as
  # `<li>second item<h2>A heading</h2></li>` — the heading disappears into the
  # bullet instead of ending the list.
  test "a heading written straight after a list is flagged" do
    issues = MarkdownDoctor.diagnose("- first item\n- second item\n## A heading\n")

    assert_equal [ :absorbed_by_list ], issues.map { |i| i[:type] }
    assert_equal 3, issues.first[:line]
    assert issues.first[:fixable], "a blank line is the only thing it can mean"
  end

  test "a code fence written straight after a list is flagged" do
    issues = MarkdownDoctor.diagnose("- one\n- two\n```ruby\ncode\n```\n")

    assert_equal [ :absorbed_by_list ], issues.map { |i| i[:type] }
  end

  test "a list still absorbs a heading through an indented continuation" do
    issues = MarkdownDoctor.diagnose("- one\n  more of item one\n## Heading\n")

    assert_equal [ :absorbed_by_list ], issues.map { |i| i[:type] }
  end

  test "a blank line above the heading is all it takes" do
    assert_empty MarkdownDoctor.diagnose("- first item\n- second item\n\n## A heading\n")
  end

  # An unindented line after a list item is lazy continuation — how a long item
  # gets wrapped. Flagging it would fire on ordinary prose.
  test "text after a list item is continuation, not an absorbed block" do
    assert_empty MarkdownDoctor.diagnose("- one\n- two\ncontinues item two\n")
  end

  test "a fence indented into a list item is deliberate" do
    assert_empty MarkdownDoctor.diagnose("- one\n    ```\n    code\n    ```\n")
  end

  test "a heading inside a fenced block is not a heading" do
    assert_empty MarkdownDoctor.diagnose("```\n- one\n## not a heading\n```\n")
  end

  test "a list that has already ended absorbs nothing" do
    assert_empty MarkdownDoctor.diagnose("- one\n\nA paragraph.\n\n## Heading\n")
  end

  # Footnotes fail quietly, which is the whole reason to check them. None of
  # these is fixable: the missing half is writing, and deleting the half that
  # exists isn't a repair.
  test "a footnote reference with no definition is flagged" do
    issues = MarkdownDoctor.diagnose("Text with a ref[^9].\n")

    assert_equal [ :orphaned_footnote ], issues.map { |i| i[:type] }
    assert_equal 1, issues.first[:line]
    assert_not issues.first[:fixable], "Roe can't write the note for them"
    assert_includes issues.first[:message], "[^9]"
  end

  test "a footnote nobody references is flagged where it is defined" do
    issues = MarkdownDoctor.diagnose("Plain text.\n\n[^1]: never referenced\n")

    assert_equal [ :unused_footnote ], issues.map { |i| i[:type] }
    assert_equal 3, issues.first[:line]
  end

  # Kramdown keeps the LAST definition, so the flag goes on the winner and says
  # so — the earlier text is what silently disappeared.
  test "a footnote defined twice is flagged at the definition that wins" do
    issues = MarkdownDoctor.diagnose("Ref[^1].\n\n[^1]: first\n\n[^1]: second\n")

    assert_equal [ :duplicate_footnote ], issues.map { |i| i[:type] }
    assert_equal 5, issues.first[:line]
  end

  test "a matched footnote pair is clean, whatever the label looks like" do
    assert_empty MarkdownDoctor.diagnose("Ref[^1].\n\n[^1]: the note\n")
    assert_empty MarkdownDoctor.diagnose("Ref[^my-note].\n\n[^my-note]: the note\n")
    assert_empty MarkdownDoctor.diagnose("Ref[^1].\n\n   [^1]: indented\n")
    assert_empty MarkdownDoctor.diagnose("Ref[^1].\n\n[^1]: line one\n    line two\n")
  end

  test "footnote syntax being shown rather than used is not a reference" do
    assert_empty MarkdownDoctor.diagnose("Write `[^1]` to make one.\n")
    assert_empty MarkdownDoctor.diagnose("```\nRef[^1] example\n```\n")
  end

  # Roe's own blocks are fences, so a footnote used inside a card would look
  # unreferenced. Telling someone to delete a note they're using is worse than
  # missing one they aren't.
  test "a footnote used inside a roe block still counts as used" do
    content = "```card\ntype: aside\ntext: Note[^1] here.\n```\n\n[^1]: used in a card\n"

    assert_empty MarkdownDoctor.diagnose(content)
  end

  test "footnote line numbers count from the top of the file" do
    issues = MarkdownDoctor.diagnose("---\ntitle: \"X\"\n---\nRef[^9] here.\n")

    assert_equal 4, issues.first[:line]
  end

  test "fixing an absorbed heading frees it from the list" do
    fixed, applied = MarkdownDoctor.new("- first item\n- second item\n## A heading\n").fix

    assert_equal [ :absorbed_by_list ], applied.map { |i| i[:type] }
    assert_equal "- first item\n- second item\n\n## A heading\n", fixed
    assert_empty MarkdownDoctor.diagnose(fixed), "and the fix holds"
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
