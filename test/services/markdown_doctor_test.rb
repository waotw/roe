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

  # Kramdown opens a code block for a fence indented up to three spaces, and it
  # doesn't care whether the closer is indented to match. Anchoring the fence
  # pattern at column zero meant an indented fence wasn't seen at all — so its
  # partner looked like a lone opener, and correct markup was reported as an
  # unclosed fence.
  test "an indented fence is still a fence" do
    body = "puts \"hi\"\n"

    [ "  ```ruby\n#{body}```\n",     # opener indented, closer flush
      "   ```ruby\n#{body}```\n",    # three spaces, the most kramdown allows
      "```ruby\n#{body}  ```\n",     # closer indented, opener flush
      "  ```ruby\n  #{body}  ```\n" ].each do |content|
      assert_empty MarkdownDoctor.diagnose(content),
        "this renders correctly and should not be reported:\n#{content}"
    end
  end

  test "an indented fence that really is unclosed is reported at its opener" do
    issues = MarkdownDoctor.diagnose("  ```ruby\nputs 1\n")

    assert_equal [ :unclosed_fence ], issues.map { |i| i[:type] }
    assert_equal 1, issues.first[:line], "the opener, not whatever followed it"
  end

  # Four spaces is an indented code block at top level and a continuation inside
  # a list or footnote — either way it isn't a fence this should be tracking.
  test "a four-space fence in a list or footnote is left alone" do
    assert_empty MarkdownDoctor.diagnose("- item\n\n    ```ruby\n    puts 1\n    ```\n")
    assert_empty MarkdownDoctor.diagnose("T[^1]\n\n[^1]: note\n\n    ```ruby\n    puts 1\n    ```\n")
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

  # --- indentation that was meant and didn't take ----------------------------
  #
  # These share a shape: the author indented something deliberately, kramdown
  # wanted a different amount, and the result still renders — just not where it
  # was put. Nothing looks broken, which is what makes them worth reporting.

  test "a fence indented into a code block is reported, once" do
    issues = MarkdownDoctor.diagnose("Text.\n\n    ```ruby\n    puts 1\n    ```\n")

    assert_equal [ :over_indented_fence ], issues.map { |i| i[:type] },
      "the closer is the same mistake, not a second one"
    assert_equal 3, issues.first[:line]
  end

  # The same four spaces under a list item or footnote is a continuation, and
  # correct. Only at top level does it turn the fence into content.
  test "an indented fence in a list or footnote is not over-indented" do
    assert_empty MarkdownDoctor.diagnose("- item\n\n    ```ruby\n    puts 1\n    ```\n")
    assert_empty MarkdownDoctor.diagnose("T[^1]\n\n[^1]: note\n\n    ```ruby\n    puts 1\n    ```\n")
  end

  # A fence at column 0 leaves the list the same way a blockquote does. Like the
  # blockquote rule, it only counts when the list carries on afterwards.
  test "a column-zero fence between list items is flagged" do
    issues = MarkdownDoctor.diagnose("- one\n\n```ruby\nputs 1\n```\n\n- two\n")

    assert_equal [ :unindented_fence_in_list ], issues.map { |i| i[:type] }
    assert_equal 3, issues.first[:line], "the opener, not the closer"
  end

  test "a fence after the last list item is just a fence" do
    assert_empty MarkdownDoctor.diagnose("- one\n- two\n\n```ruby\nputs 1\n```\n")
  end

  test "a footnote continuation short of four spaces is flagged and fixable" do
    issues = MarkdownDoctor.diagnose("T[^1]\n\n[^1]: first\n\n  second para\n")

    assert_equal [ :under_indented_footnote ], issues.map { |i| i[:type] }
    assert issues.first[:fixable], "there is one right answer: four spaces"

    fixed, = MarkdownDoctor.new("T[^1]\n\n[^1]: first\n\n  second para\n").fix

    assert_equal "T[^1]\n\n[^1]: first\n\n    second para\n", fixed
    assert_empty MarkdownDoctor.diagnose(fixed)
  end

  # An unindented line is also how a footnote ends, so it isn't a failed
  # continuation. (Being *below* the notes is its own report —
  # content_after_footnotes — tested under "footnote placement".)
  test "body text after a footnote is not a failed continuation" do
    continuation = %i[under_indented_footnote unindented_footnote_line]

    assert_empty types("T[^1]\n\n[^1]: first\n\nBody text.\n") & continuation
    assert_empty MarkdownDoctor.diagnose("T[^1]\n\n[^1]: first\n\n    second para\n")
  end

  # A child has to reach the column its parent's text starts at: two for `- `,
  # three for `1. `. `1. a` over `  1. b` looks nested and isn't.
  test "a list item indented too little to nest is flagged" do
    assert_equal [ :list_indent_too_shallow ],
      MarkdownDoctor.diagnose("1. a\n  1. b\n").map { |i| i[:type] }
    assert_equal [ :list_indent_too_shallow ],
      MarkdownDoctor.diagnose("- a\n - b\n").map { |i| i[:type] }
  end

  # Not fixable: indenting it further and removing the indent are both one edit,
  # and only the author knows which was meant.
  test "a shallow list indent is a warning, not a fix" do
    assert_not MarkdownDoctor.diagnose("1. a\n  1. b\n").first[:fixable]
  end

  test "list nesting that works says nothing" do
    assert_empty MarkdownDoctor.diagnose("- a\n  - b\n")
    assert_empty MarkdownDoctor.diagnose("1. a\n   1. b\n")
    assert_empty MarkdownDoctor.diagnose("- a\n  - b\n    - c\n"), "three real levels"
    assert_empty MarkdownDoctor.diagnose("- a\n- b\n- c\n"), "plain siblings"
    assert_empty MarkdownDoctor.diagnose("- a\n  - b\n- c\n"), "nested, then back out"
  end

  # The sample post is what the editor's panel gets tested against by hand, so
  # a rule missing from it is a rule nobody looks at. Cheaper to fail here than
  # to notice months later that a check has never been seen working.
  test "the sample post exercises every rule" do
    issues = MarkdownDoctor.diagnose(
      File.read(Rails.root.join("test/fixtures/files/markdown_doctor_sample.md")),
    )

    # Text after the notes can't be shown here: it needs the notes to be the
    # last thing before it, and the sample ends on an unclosed fence on
    # purpose. It has its own tests under "footnote placement". The link check
    # needs a rendered page, which the sample isn't given.
    expected = MarkdownDoctor::ISSUE_TYPES.keys - %i[content_after_footnotes broken_anchor_link]
    assert_empty expected - issues.map { |i| i[:type] },
      "add a section to markdown_doctor_sample.md for the rules listed above"
    assert issues.any? { |i| i[:fixable] }, "and something for Fix All to do"
  end

  # Fix All has to survive a document with this much wrong in it, and leave
  # nothing fixable behind.
  test "fixing the sample post settles in one pass" do
    content = File.read(Rails.root.join("test/fixtures/files/markdown_doctor_sample.md"))
    fixed, applied = MarkdownDoctor.new(content).fix

    assert_predicate applied.size, :positive?
    assert_empty MarkdownDoctor.diagnose(fixed).select { |i| i[:fixable] }
    assert_equal fixed, MarkdownDoctor.new(fixed).fix.first, "and running it again changes nothing"
  end

  test "indentation inside a code block is content" do
    assert_empty MarkdownDoctor.diagnose("```\n    ```ruby\n```\n")
    assert_empty MarkdownDoctor.diagnose("```\n1. a\n  1. b\n```\n")
  end

  # --- footnote placement --------------------------------------------------
  # kramdown renders every footnote at the end of the page, whatever follows
  # it in the file. So text written below the notes shows above them, and a
  # line typed under a note without its indent shows in the body.

  test "text below the last footnote is flagged where it starts" do
    content = "Body[^1].\n\n[^1]: The note.\n\nStray paragraph.\n\n- stray item\n"
    issue = MarkdownDoctor.diagnose(content).find { |i| i[:type] == :content_after_footnotes }

    assert issue
    assert_equal 5, issue[:line]
    assert issue[:fixable]
  end

  test "Fix All moves text below the notes above them, unchanged" do
    content = "Body[^1] and[^2].\n\n[^1]: One.\n\n[^2]: Two.\n\nStray paragraph.\n\n- stray item\n"
    fixed, applied = MarkdownDoctor.fix(content)

    assert_equal "Body[^1] and[^2].\n\nStray paragraph.\n\n- stray item\n\n[^1]: One.\n\n[^2]: Two.\n", fixed
    assert_equal [ :content_after_footnotes ], applied.map { |i| i[:type] }
    assert_equal fixed, MarkdownDoctor.fix(fixed).first, "and running it again changes nothing"
  end

  test "a note's indented second paragraph isn't text after the notes" do
    assert_empty MarkdownDoctor.diagnose("Body[^1].\n\n[^1]: First.\n\n    Second paragraph.\n")
  end

  test "a heading after the notes starts a section on purpose" do
    assert_empty MarkdownDoctor.diagnose("Body[^1].\n\n[^1]: The note.\n\n## Appendix\n\nText.\n")
  end

  test "notes written beside the paragraphs that use them are left alone" do
    assert_empty MarkdownDoctor.diagnose("One[^1].\n\n[^1]: Note one.\n\nTwo[^2].\n\n[^2]: Note two.\n")
  end

  test "text after the notes is only moved up to the next heading" do
    content = "Body[^1].\n\n[^1]: The note.\n\nStray.\n\n## Appendix\n\nMore.\n"
    fixed, = MarkdownDoctor.fix(content)

    assert_equal "Body[^1].\n\nStray.\n\n[^1]: The note.\n\n## Appendix\n\nMore.\n", fixed
  end

  test "an unclosed fence below the notes is reported but not moved" do
    content = "Body[^1].\n\n[^1]: The note.\n\n```ruby\nputs 1\n"
    issue = MarkdownDoctor.diagnose(content).find { |i| i[:type] == :content_after_footnotes }

    assert issue
    assert_not issue[:fixable], "moved above the notes, the fence would swallow them"
    assert_equal content, MarkdownDoctor.fix(content).first
  end

  test "a line straight under a note without its indent is flagged and indented" do
    content = "Body[^1].\n\n[^1]: The note\ncarries on here.\n"
    issue = MarkdownDoctor.diagnose(content).find { |i| i[:type] == :unindented_footnote_line }

    assert_equal 4, issue[:line]
    assert_equal "Body[^1].\n\n[^1]: The note\n    carries on here.\n", MarkdownDoctor.fix(content).first
  end

  test "a heading straight under a note isn't pulled into it" do
    types = types("Body[^1].\n\n[^1]: The note.\n## Next section\n")

    assert_not_includes types, :unindented_footnote_line
  end

  test "front matter doesn't throw the move off" do
    content = "---\ntitle: x\n---\nBody[^1].\n\n[^1]: The note.\n\nStray.\n"
    fixed, = MarkdownDoctor.fix(content)

    assert_equal "---\ntitle: x\n---\nBody[^1].\n\nStray.\n\n[^1]: The note.\n", fixed
  end

  # --- formatting that doesn't close -----------------------------------------
  # Measured against the renderer: ==highlight== can't cross a line break (it's
  # matched a line at a time), while **bold**, _em_ and ~~strike~~ can. None of
  # them survives a blank line, which ends the paragraph.

  test "a highlight that closes on a later line is flagged at its opening" do
    issues = MarkdownDoctor.diagnose("Intro.\n\nSome ==marked\ntext== here.\n")

    assert_equal [ :marker_across_lines ], issues.map { |i| i[:type] }
    assert_equal 3, issues.first[:line]
    assert_not issues.first[:fixable], "where it was meant to close is the writer's call"
  end

  test "bold, strike and highlight that never close in their paragraph are flagged" do
    assert_equal [ 1, 3 ], MarkdownDoctor.diagnose("Some **bold\n\ntext** here.\n").map { |i| i[:line] }
    assert_includes types("Some ~~struck text here.\n"), :marker_across_lines
    assert_includes types("Some ==marked text here.\n"), :marker_across_lines
  end

  test "formatting that renders fine says nothing" do
    [
      "Some **bold\ntext** here.\n",          # bold can cross a line break
      "A ==marked== word and **bold** one.\n",
      "If a == b and 2 ** 3, then.\n",        # spaced both sides: not a marker
      "Title\n=====\n\nText.\n",              # setext underline
      "Some ***both*** here.\n",
      "Use `a==b` and `**` here.\n",          # in code
      "Literal \\*\\* and \\=\\= here.\n",    # escaped
      "<a href=\"?q==x\">x</a>\n",            # an attribute
      "snake__case__name here.\n",
      "```\n**open\n```\n",                   # in a code block
      "- **one** item\n- two **bold**\n"
    ].each do |content|
      assert_not_includes types(content), :marker_across_lines, content.inspect
    end
  end

  test "each list item is its own paragraph" do
    assert_includes types("- **one\n- two**\n"), :marker_across_lines
  end

  # --- in-page links ---------------------------------------------------------
  # Checked against the ids of the rendered page, which the caller passes in.
  # Without them (the CLI, which doesn't render) the check is skipped.

  test "a link to an id that's on the page says nothing" do
    assert_empty MarkdownDoctor.diagnose("See [setup](#setup).\n", page_ids: %w[setup])
  end

  test "a link to an id that isn't on the page is flagged, with the likely one" do
    issue = MarkdownDoctor.diagnose("See [x](#just-text).\n", page_ids: %w[aside just-text-example post-link])
                          .find { |i| i[:type] == :broken_anchor_link }

    assert_equal 1, issue[:line]
    assert_includes issue[:message], "#just-text-example"
    assert_not issue[:fixable]
  end

  test "no suggestion when nothing is close" do
    issue = MarkdownDoctor.diagnose("[x](#zzzzzz)\n", page_ids: %w[intro setup])
                          .find { |i| i[:type] == :broken_anchor_link }

    assert_not_includes issue[:message], "did you mean"
  end

  test "html links, encoded anchors and links to other pages" do
    assert_includes types_with_ids("<a href=\"#nope\">x</a>\n", %w[intro]), :broken_anchor_link
    assert_empty types_with_ids("[x](#caf%C3%A9)\n", %w[café])
    assert_empty types_with_ids("[x](/about#team)\n", %w[intro]), "only this page is rendered"
    assert_empty types_with_ids("Use `[x](#nope)` here.\n", %w[intro]), "in code it's an example"
  end

  test "without page ids the link check is skipped" do
    assert_not_includes types("[x](#nope)\n"), :broken_anchor_link
  end

  private

  def types_with_ids(content, ids)
    MarkdownDoctor.diagnose(content, page_ids: ids).map { |i| i[:type] }
  end
end
