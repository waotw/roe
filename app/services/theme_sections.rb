# The section headings in a theme's CSS, which the theme editor lists as its
# table of contents.
#
#   /* ==== NAME ==== */    a section, uppercase, on one line
#   /* ---- Name ---- */    a subsection inside it, on one line
#
# The file's first comment opens with "/* ==== THEME INFO ====" and carries
# on over several lines: it's also the header the update system reads (see
# ShippedFileInspector), which has to stay one comment.
#
# A convention, not a rule. The themes Roe ships follow it, and a test keeps
# them in step. A site's own theme can add, drop or reorder sections freely;
# whatever it writes in this format shows in the list.
module ThemeSections
  Heading = Struct.new(:level, :name, :line, keyword_init: true)

  SECTION = %r{\A/\* ==== (.+?) ====(?: \*/)?\s*\z}
  SUBSECTION = %r{\A/\* ---- (.+?) ---- \*/\s*\z}

  module_function

  def parse(css)
    css.to_s.each_line.with_index(1).filter_map do |text, line|
      if (m = text.match(SECTION))
        Heading.new(level: 1, name: m[1], line: line)
      elsif (m = text.match(SUBSECTION))
        Heading.new(level: 2, name: m[1], line: line)
      end
    end
  end
end
