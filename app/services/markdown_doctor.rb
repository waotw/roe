# frozen_string_literal: true

# Diagnostics for Roe-authored Markdown.
#
# Checks:
#   1. Fence validity — backtick fences must be 3 or 4 backticks long (1 is
#      allowed inline but not alone on a line; 2 and 5+ are invalid).
#   2. Fence matching — an opening fence must be closed by a fence of the same
#      length. A 4-backtick fence should contain a nested 3-backtick fence;
#      otherwise it should be 3.
#   3. List spacing — a list item immediately following a non-list element
#      without a blank line in between. Kramdown/Roe needs the blank line.
#
# Takes CONTENT, not a path: the editor lints the text in the textarea, which
# hasn't been saved yet, so reading from disk would check the wrong thing.
# .diagnose_file is the convenience for callers that do have a file.
#
# DEPENDENCY-FREE ON PURPOSE. bin/roe-markdown-doctor requires this file
# directly rather than booting Rails, so it must stay plain Ruby — no
# ActiveSupport (`present?`, `blank?`) and nothing from the app.
class MarkdownDoctor
  ISSUE_TYPES = {
    invalid_fence_length: "Invalid fence length",
    mismatched_fence: "Mismatched fence closer",
    nested_same_length_fence: "Nested fence uses same-length outer fence",
    four_fence_without_nesting: "4-backtick fence with no nested 3-backtick block",
    unclosed_fence: "Unclosed fence",
    list_spacing: "List item without preceding blank line",
    unindented_blockquote_in_list: "Unindented blockquote breaking a list",
    absorbed_by_list: "Heading or code block pulled into the list above",
    orphaned_footnote: "Footnote reference with no definition",
    unused_footnote: "Footnote defined but never referenced",
    duplicate_footnote: "Footnote defined more than once",
    over_indented_fence: "Fence indented far enough to become a code block",
    unindented_fence_in_list: "Unindented code fence breaking a list",
    under_indented_footnote: "Footnote continuation not indented enough",
    list_indent_too_shallow: "List item indented but not enough to nest"
  }.freeze

  # Which issues Fix All is allowed to touch.
  #
  # Only where there is exactly one correct rewrite and no guess about intent.
  # The fence problems are all excluded on purpose: an unclosed fence has no
  # knowable closing point, and choosing wrongly swallows the rest of the
  # document into a code block. Same for a mismatched closer — changing the
  # opener and changing the closer mean different things, and only the author
  # knows which was meant. Those stay as warnings.
  FIXABLE_TYPES = %i[
    list_spacing
    unindented_blockquote_in_list
    absorbed_by_list
    under_indented_footnote
  ].freeze

  def self.fixable?(type)
    FIXABLE_TYPES.include?(type.to_sym)
  end

  # `[^label]` anywhere in a line, and `[^label]:` starting one. Kramdown takes
  # any label without whitespace — digits, dashes and underscores all work — and
  # allows the definition to be indented.
  FOOTNOTE_REF_RE = /\[\^([^\]\s]+)\]/
  FOOTNOTE_DEF_RE = /^\s*\[\^([^\]\s]+)\]:/
  INLINE_CODE_RE = /`[^`]*`/

  # Up to three spaces of indentation, because that's what kramdown accepts —
  # a fence indented that far still opens a code block. Anchoring at column
  # zero meant an indented fence wasn't seen at all, so its partner looked like
  # a lone opener and every one of them was reported as an unclosed fence.
  #
  # Four or more is deliberately not a fence: at top level that's an indented
  # code block, and inside a list item or footnote it's a continuation, where
  # the fence belongs to a context this doesn't track.
  #
  # The indent is not captured, so the group numbers every check reads stay put.
  FENCE_RE = /^ {0,3}(\`+)([^\`]*?)\s*$/
  LIST_RE  = /^(\s*)(?:[-*+]|\d+\.)\s+/
  # Indent, marker and the space after it. The column the item's own content
  # starts at is what a child has to reach to nest under it.
  LIST_PARTS_RE = /^( *)([-*+]|\d+\.)( +)/
  # Four or more spaces: too far to be a fence, so kramdown reads it as an
  # indented code block instead of opening one.
  OVER_INDENTED_FENCE_RE = /^( {4,})(`{3,})/
  BLOCKQUOTE_RE = /^>/
  HEADING_RE = /^\s*\#{1,6}(\s|$)/
  SETEXT_UNDERLINE_RE = /^\s*(=+|-+)\s*$/
  HR_RE = /^\s*(?:-{3,}|\*{3,}|_{3,})\s*$/

  def self.diagnose(content)
    new(content).diagnose
  end

  def self.diagnose_file(path)
    new(File.read(path)).diagnose
  end

  def initialize(content)
    @lines = content.to_s.lines
    @issues = []
  end

  def diagnose
    skip_front_matter!
    check_fences
    check_list_spacing
    check_absorbed_blocks
    check_list_interruptions
    check_footnotes
    check_indentation
    @issues.each { |i| i[:fixable] = self.class.fixable?(i[:type]) }
    @issues
  end

  # Content with every fixable issue corrected, and the issues it corrected.
  # Anything not in FIXABLE_TYPES is left exactly as written.
  #
  # Returns [fixed_content, applied_issues]. Applying to already-clean content
  # returns it unchanged, so this is safe to run repeatedly.
  def fix
    issues = diagnose
    fixable = issues.select { |i| i[:fixable] }
    return [ @lines.join, [] ] if fixable.empty?

    # Work back to front so earlier line numbers stay valid as lines shift.
    out = @lines.dup
    fixable.sort_by { |i| -i[:line] }.each do |issue|
      idx = issue[:line] - 1
      next unless out[idx]

      case issue[:type]
      when :list_spacing, :absorbed_by_list
        # Both want the same thing: a blank line above. Insert rather than
        # replace so the line above is untouched.
        out.insert(idx, "\n")
      when :unindented_blockquote_in_list
        # A `>` at column 0 escapes the list; four spaces keeps it in the item.
        out[idx] = "    " + out[idx]
      when :under_indented_footnote
        # Already indented, just not to four. Top it up rather than prepending,
        # so the line ends up at four rather than four-plus-what-was-there.
        out[idx] = "    " + out[idx].sub(/\A[ \t]+/, "")
      end
    end

    [ out.join, fixable ]
  end

  def self.fix(content)
    new(content).fix
  end

  private

  # Skip YAML front matter (--- ... ---) so we don't treat it as Markdown.
  def skip_front_matter!
    return unless @lines.first&.strip == "---"

    @lines.each_with_index do |line, idx|
      next if idx == 0
      if line.strip == "---"
        @front_matter_lines = idx + 1
        break
      end
    end
  end

  def effective_lines
    @effective_lines ||= @lines[(@front_matter_lines || 0)..-1] || []
  end

  def effective_line_number(idx)
    idx + 1 + (@front_matter_lines || 0)
  end

  def check_fences
    stack = [] # each: { length, line, has_nested_three }

    effective_lines.each_with_index do |line, idx|
      match = line.match(FENCE_RE)
      next unless match

      length = match[1].length
      info = match[2].strip
      line_num = effective_line_number(idx)

      if length == 1
        if line.strip == "`"
          @issues << {
            type: :invalid_fence_length,
            line: line_num,
            message: "Single backtick alone on a line (use 3+ backticks for a fence)"
          }
        end
        next
      end

      if length == 2
        @issues << {
          type: :invalid_fence_length,
          line: line_num,
          message: "2-backtick fence (minimum is 3)"
        }
        next
      end

      if length > 4
        @issues << {
          type: :invalid_fence_length,
          line: line_num,
          message: "Fence with #{length} backticks (use 3 or 4)"
        }
        next
      end

      has_info = !info.empty?

      if has_info
        if stack.any? && length == stack.last[:length]
          @issues << {
            type: :nested_same_length_fence,
            line: line_num,
            message: "Nested #{length}-backtick fence inside #{length}-backtick block; use a longer outer fence"
          }
        end

        if stack.any? && stack.last[:length] == 4 && length == 3
          stack.last[:has_nested_three] = true
        end

        stack << { length: length, line: line_num, has_nested_three: false }
      else
        if stack.empty?
          stack << { length: length, line: line_num, has_nested_three: false }
        elsif length == stack.last[:length]
          popped = stack.pop
          if popped[:length] == 4 && !popped[:has_nested_three]
            @issues << {
              type: :four_fence_without_nesting,
              line: popped[:line],
              message: "4-backtick block has no nested 3-backtick block; use 3 backticks unless nesting"
            }
          end
        else
          @issues << {
            type: :mismatched_fence,
            line: line_num,
            message: "Mismatched closing fence: expected #{stack.last[:length]} backticks to match opener at line #{stack.last[:line]}, found #{length}"
          }
          stack.pop
        end
      end
    end

    stack.each do |frame|
      @issues << {
        type: :unclosed_fence,
        line: frame[:line],
        message: "Unclosed #{frame[:length]}-backtick fence"
      }
    end
  end

  def check_list_spacing
    inside_code_block = false
    code_block_fence_len = nil

    effective_lines.each_with_index do |line, idx|
      line_num = effective_line_number(idx)

      # Track fenced code blocks so we don't flag list-like lines inside them.
      if (match = line.match(FENCE_RE))
        length = match[1].length
        if inside_code_block && length >= code_block_fence_len
          inside_code_block = false
          code_block_fence_len = nil
        elsif !inside_code_block
          inside_code_block = true
          code_block_fence_len = length
        end
        next
      end

      next if inside_code_block
      next unless line.match?(LIST_RE)

      # Only top-level list items need a blank line before them. Nested list
      # items (indented under a parent item) are valid without one.
      current_indent = line_indent(line)
      next if current_indent > 0

      # If the line immediately before this list item is blank, spacing is fine.
      next if idx > 0 && effective_lines[idx - 1].strip.empty?

      prev_idx = previous_non_blank_with_indent_leq(effective_lines, idx, 0)
      next unless prev_idx

      prev_line = effective_lines[prev_idx]
      next if list_item?(prev_line)
      next if prev_line.match?(HEADING_RE) || prev_line.match?(SETEXT_UNDERLINE_RE) || prev_line.match?(HR_RE)

      @issues << {
        type: :list_spacing,
        line: line_num,
        message: "List item is not preceded by a blank line"
      }
    end
  end

  # The mirror of check_list_spacing: a heading or code fence written straight
  # after a list, with no blank line, is swallowed by the last list item.
  #
  #     - first item
  #     - second item
  #     ## A heading      ->  <li>second item<h2>A heading</h2></li>
  #
  # A blank line is all it takes to end the list, and there's no reading of this
  # where the heading was meant to be part of the bullet, so it's fixable.
  #
  # Plain text is deliberately not flagged: an unindented line after a list item
  # is lazy continuation, which is how a long item gets wrapped over two lines.
  # Thematic breaks are left out too — `---` after a list is also a setext
  # underline, and the rule shouldn't guess which was meant.
  def check_absorbed_blocks
    in_list = false
    previous_blank = true
    inside_code_block = false
    code_block_fence_len = nil

    effective_lines.each_with_index do |line, idx|
      blank = line.strip.empty?
      fence = line.match(FENCE_RE)

      if !inside_code_block && in_list && !previous_blank && absorbing_block?(line)
        @issues << {
          type: :absorbed_by_list,
          line: effective_line_number(idx),
          message: "Needs a blank line above it, or the list above swallows it"
        }
      end

      if fence
        length = fence[1].length
        if inside_code_block && length >= code_block_fence_len
          inside_code_block = false
          code_block_fence_len = nil
        elsif !inside_code_block
          inside_code_block = true
          code_block_fence_len = length
        end
      end

      unless inside_code_block
        if blank
          # A blank line alone doesn't close a list — loose lists are full of
          # them. It only ends when unindented, non-list content follows one.
        elsif line.match?(LIST_RE)
          in_list = true
        elsif line_indent(line) > 0
          # Indented continuation: still inside the item.
        elsif previous_blank
          in_list = false
        end
      end

      previous_blank = blank
    end
  end

  def absorbing_block?(line)
    return false unless line_indent(line).zero?

    line.match?(HEADING_RE) || line.match?(FENCE_RE)
  end

  # Detect blockquotes at column 0 that appear between two top-level list
  # items. In kramdown a `>` at column 0 breaks out of the list; to keep it
  # inside a list item it must be indented by 4 spaces.
  def check_list_interruptions
    inside_code_block = false
    code_block_fence_len = nil
    pending_blockquotes = []
    last_list_item_line = nil

    effective_lines.each_with_index do |line, idx|
      line_num = effective_line_number(idx)

      # Track fenced code blocks
      if (match = line.match(FENCE_RE))
        length = match[1].length
        if inside_code_block && length >= code_block_fence_len
          inside_code_block = false
          code_block_fence_len = nil
        elsif !inside_code_block
          # A fence at column 0 leaves the list the same way a blockquote does,
          # and for the same reason — it isn't indented into the item. Only the
          # opener is recorded; the closer is part of the same block.
          if last_list_item_line && line_indent(line).zero?
            pending_blockquotes << { line: line_num, type: :unindented_fence_in_list, what: "Code fence" }
          end
          inside_code_block = true
          code_block_fence_len = length
        end
        next
      end
      next if inside_code_block

      # Blockquote at column 0 between list items likely breaks the list
      if line.match?(BLOCKQUOTE_RE) && line_indent(line) == 0
        if last_list_item_line
          pending_blockquotes << { line: line_num, type: :unindented_blockquote_in_list, what: "Blockquote" }
        end
        next
      end

      # Top-level list item confirms any pending blockquotes broke the list
      if line.match?(LIST_RE) && line_indent(line) == 0
        pending_blockquotes.each do |bq|
          @issues << {
            type: bq[:type],
            line: bq[:line],
            message: "#{bq[:what]} at line #{bq[:line]} breaks out of list that continues at line #{line_num}; indent it by 4 spaces to keep it inside the list item"
          }
        end
        pending_blockquotes = []
        last_list_item_line = line_num
        next
      end

      # Heading, HR, or setext at column 0 ends list context
      if line.match?(HEADING_RE) || line.match?(SETEXT_UNDERLINE_RE) || line.match?(HR_RE)
        if line_indent(line) == 0
          pending_blockquotes = []
          last_list_item_line = nil
        end
      end
    end
  end

  # Footnotes fail quietly, which is what makes them worth checking. A reference
  # with no definition prints as `[^9]` in the finished post; a definition
  # nobody references renders nothing at all, so a note someone wrote simply
  # isn't there. None of the three is fixable — the missing half is writing, and
  # deleting the half that exists is not a repair.
  def check_footnotes
    references = {}   # label => line it first appears on, prose only
    definitions = {}  # label => line of its first definition
    used_anywhere = {} # label => true, including inside fences — see below

    scan_lines do |line, line_num, inside_code_block|
      # `[^1]` written inside a code span is being shown, not used.
      body = line.gsub(INLINE_CODE_RE, "")

      if (definition = body.match(FOOTNOTE_DEF_RE))
        label = definition[1]

        unless inside_code_block
          if definitions.key?(label)
            @issues << {
              type: :duplicate_footnote,
              line: line_num,
              message: "Footnote [^#{label}] is defined twice, and this one wins"
            }
          else
            definitions[label] = line_num
          end
        end

        # The definition names its own label, which isn't a reference to it.
        body = body.sub(FOOTNOTE_DEF_RE, "")
      end

      body.scan(FOOTNOTE_REF_RE).flatten.each do |label|
        used_anywhere[label] = true
        next if inside_code_block

        references[label] ||= line_num
      end
    end

    references.each do |label, line|
      next if definitions.key?(label)

      @issues << {
        type: :orphaned_footnote,
        line: line,
        message: "Footnote [^#{label}] has no definition, so it prints as text"
      }
    end

    # Generous on purpose: a reference inside a fence still counts as use here.
    # Roe's own blocks are fences, so a footnote used inside a card would
    # otherwise look unreferenced — and telling someone to delete a note they
    # are using is worse than missing one they aren't.
    definitions.each do |label, line|
      next if used_anywhere.key?(label)

      @issues << {
        type: :unused_footnote,
        line: line,
        message: "Footnote [^#{label}] is never referenced, so it won't appear"
      }
    end
  end

  # Walk the body with fenced-code state tracked, which every check needs and
  # each one used to repeat.
  def scan_lines
    inside_code_block = false
    code_block_fence_len = nil

    effective_lines.each_with_index do |line, idx|
      fence = line.match(FENCE_RE)
      yield line, effective_line_number(idx), inside_code_block

      next unless fence

      length = fence[1].length
      if inside_code_block && length >= code_block_fence_len
        inside_code_block = false
        code_block_fence_len = nil
      elsif !inside_code_block
        inside_code_block = true
        code_block_fence_len = length
      end
    end
  end

  # Indentation that was clearly meant and didn't take.
  #
  # These share a shape: the author indented something on purpose, kramdown
  # needed a different amount, and the result still renders — just not where it
  # was put. Nothing looks broken, which is what makes them worth reporting.
  def check_indentation
    inside_code_block = false
    code_block_fence_len = nil
    previous_item = nil
    over_indented = nil

    effective_lines.each_with_index do |line, idx|
      fence = line.match(FENCE_RE)
      line_num = effective_line_number(idx)

      unless inside_code_block
        over_indented = check_over_indented_fence(line, idx, line_num, over_indented)
        check_footnote_continuation(line, idx, line_num)
        previous_item = check_list_nesting(line, line_num, previous_item)
      end

      next unless fence

      length = fence[1].length
      if inside_code_block && length >= code_block_fence_len
        inside_code_block = false
        code_block_fence_len = nil
      elsif !inside_code_block
        inside_code_block = true
        code_block_fence_len = length
      end
    end
  end

  # Four spaces or more and kramdown reads the line as an indented code block,
  # so the fence is printed rather than obeyed — you get backticks inside your
  # code block. Only at top level: the same four spaces under a list item or a
  # footnote is a continuation, and correct.
  # `open` is the backtick count of an over-indented fence still waiting for its
  # closer, so the pair is reported once rather than at both ends — the closer
  # is the same mistake, not a second one. Returned for the next line.
  def check_over_indented_fence(line, idx, line_num, open)
    match = line.match(OVER_INDENTED_FENCE_RE)
    return open unless match

    length = match[2].length
    return nil if open && length >= open
    return open if open
    return nil if continuation_context(idx)

    @issues << {
      type: :over_indented_fence,
      line: line_num,
      message: "Fence indented #{match[1].length} spaces — four or more makes a code block instead of opening one"
    }
    length
  end

  # A footnote's continuation has to reach four spaces. One to three is someone
  # aiming for it and missing, and the paragraph silently leaves the note.
  # An unindented line isn't reported: that's also how a footnote ends.
  def check_footnote_continuation(line, idx, line_num)
    return if line.strip.empty?

    indent = line_indent(line)
    return unless indent.between?(1, 3)
    return unless continuation_context(idx) == :footnote

    @issues << {
      type: :under_indented_footnote,
      line: line_num,
      message: "Indented #{indent} #{indent == 1 ? 'space' : 'spaces'}, so this leaves the footnote — a continuation needs four"
    }
  end

  # A child item has to reach the column its parent's own text starts at, which
  # is two for `- ` and three for `1. `. Indented less than that and it stays a
  # sibling — `1. a` over `  1. b` looks nested and isn't.
  #
  # Returns the item to compare the next one against.
  def check_list_nesting(line, line_num, previous_item)
    parts = line.match(LIST_PARTS_RE)
    return previous_item unless parts

    indent = parts[1].length
    item = { indent: indent, content_column: parts[0].length }

    if previous_item && indent > previous_item[:indent] && indent < previous_item[:content_column]
      @issues << {
        type: :list_indent_too_shallow,
        line: line_num,
        message: "Indented #{indent} past the item above but its text starts at #{previous_item[:content_column]}, so this stays a sibling rather than nesting"
      }
      # Compare the next item against the parent, not against this one — its
      # indent didn't establish a level.
      return previous_item
    end

    # A shallower item closes the deeper ones; the nearest enclosing item is
    # what the next one has to clear.
    return item if previous_item.nil? || indent >= previous_item[:indent]

    item
  end

  # Whether an indented line is a continuation of something, which is what
  # decides whether its indentation is deliberate or a mistake. Four spaces
  # under a list item or a footnote is a continuation; the same four spaces at
  # top level is a code block.
  def continuation_context(idx)
    i = idx - 1
    while i >= 0
      line = effective_lines[i]

      if line.strip.empty?
        i -= 1
        next
      end
      return :footnote if line.match?(FOOTNOTE_DEF_RE)
      return :list if line.match?(LIST_RE) && line_indent(line).zero?
      return nil if line_indent(line).zero?

      i -= 1
    end
    nil
  end

  def line_indent(line)
    line.to_s[/^\s*/].gsub("\t", "    ").length
  end

  def list_item?(line)
    line.match?(LIST_RE)
  end

  def previous_non_blank_with_indent_leq(lines, start_idx, max_indent)
    idx = start_idx - 1
    while idx >= 0
      line = lines[idx]
      return idx if !line.strip.empty? && line_indent(line) <= max_indent
      idx -= 1
    end
    nil
  end
end
