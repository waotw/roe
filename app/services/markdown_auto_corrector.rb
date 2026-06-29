# Reusable Markdown auto-corrections.
#
# Intended for use by the Roe Markdown Doctor script, the editor, and any
# model that wants to normalize user-authored Markdown before storing or
# rendering it. Keep methods pure: they take a Markdown string and return a
# corrected Markdown string; they never touch the database or filesystem.
module MarkdownAutoCorrector
  extend self

  FENCE_RE = /^(``+)([^`]*?)\s*$/
  LIST_RE  = /^(\s*)(?:[-*+]|\d+\.)\s+/
  HEADING_RE = /^\s*\#{1,6}(\s|$)/
  SETEXT_UNDERLINE_RE = /^\s*(=+|-+)\s*$/
  HR_RE = /^\s*(?:-{3,}|\*{3,}|_{3,})\s*$/

  # Inserts a blank line before any list item that is directly adjacent to a
  # non-list element without a blank line in between. Kramdown (and therefore
  # Roe) needs that blank line to recognize the list.
  #
  # The correction skips content inside fenced code blocks and is idempotent:
  # running it twice on the same text produces the same result.
  def fix_list_spacing(text)
    lines = text.lines
    ending = dominant_line_ending(text)
    result = []
    inside_code_block = false
    code_block_fence_len = nil

    lines.each_with_index do |line, idx|
      if (match = line.match(FENCE_RE))
        length = match[1].length
        if inside_code_block && length >= code_block_fence_len
          inside_code_block = false
          code_block_fence_len = nil
        elsif !inside_code_block
          inside_code_block = true
          code_block_fence_len = length
        end
        result << line
        next
      end

      if inside_code_block
        result << line
        next
      end

      if list_item?(line)
        current_indent = line_indent(line)
        next unless current_indent == 0

        prev_idx = previous_non_blank_with_indent_leq(lines, idx, 0)
        prev_line = lines[prev_idx]

        if prev_idx && !list_item?(prev_line) &&
           !prev_line.match?(HEADING_RE) &&
           !prev_line.match?(SETEXT_UNDERLINE_RE) &&
           !prev_line.match?(HR_RE) &&
           !blank_line?(lines[idx - 1])
          result << ending
        end
      end

      result << line
    end

    result.join
  end

  private

  def list_item?(line)
    line.match?(LIST_RE)
  end

  def blank_line?(line)
    line.to_s.strip.empty?
  end

  def line_indent(line)
    line.to_s[/^\s*/].gsub("\t", "    ").length
  end

  def previous_non_blank_with_indent_leq(lines, start_idx, max_indent)
    idx = start_idx - 1
    while idx >= 0
      line = lines[idx]
      return idx if !blank_line?(line) && line_indent(line) <= max_indent
      idx -= 1
    end
    nil
  end

  def dominant_line_ending(text)
    crlf = text.scan("\r\n").length
    lf   = text.count("\n") - crlf
    crlf > lf ? "\r\n" : "\n"
  end
end
