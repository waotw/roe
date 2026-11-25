# Keeps French-style punctuation on the same line as the word before it.
#
# French puts a space before ? ! : ; » and after «. Written as an ordinary
# space, a browser may break the line there and leave the ? alone at the
# start of the next one. This swaps those spaces for no-break spaces in
# rendered HTML, the widths French typesetting uses: the narrow no-break
# space (U+202F) before ? ! ; » and after «, a full-width no-break space
# (U+00A0) before :. Files aren't changed.
#
# English rarely puts a space before these marks; where it does (Roe's docs
# write "like this ↓ :"), keeping the mark on the line is better there too.
#
# Only text is changed: tags and their attributes (links, image addresses)
# are left alone, and so is everything inside <pre>, <code>, <kbd>, <samp>,
# <script>, <style> and <textarea>, so code examples stay exact.
module PunctuationSpaces
  NBSP = "\u00A0".freeze
  NARROW = "\u202F".freeze

  SKIP = %w[pre code kbd samp script style textarea].freeze
  TAG = /(<!--.*?-->|<[^>]*>)/m

  # Spaces (ordinary or already no-break) before the closing marks, and after
  # the opening guillemet. Entities cover kramdown's typographic output.
  SPACES = "[ \u00A0\u202F]+"
  BEFORE_COLON = /#{SPACES}(?=:)/
  BEFORE = /#{SPACES}(?=[?!;»]|&raquo;|&#187;)/
  AFTER = /(«|&laquo;|&#171;)#{SPACES}/

  module_function

  def apply(html)
    return html if html.nil? || html.empty?
    return html unless html.match?(/[?!:;»]|&raquo;|&#187;|«|&laquo;|&#171;/)

    depth = 0
    out = html.to_s.split(TAG).map do |part|
      if part.start_with?("<")
        depth = track(part, depth)
        part
      elsif depth.zero?
        part.gsub(BEFORE_COLON, NBSP).gsub(BEFORE, NARROW)
            .gsub(AFTER) { "#{Regexp.last_match(1)}#{NARROW}" }
      else
        part
      end
    end.join
    html.html_safe? ? out.html_safe : out
  end

  # How deep we are inside elements whose text is left alone.
  def track(tag, depth)
    name = tag[%r{\A</?([a-zA-Z][a-zA-Z0-9-]*)}, 1]&.downcase
    return depth unless name && SKIP.include?(name)
    return depth if tag.end_with?("/>")

    tag.start_with?("</") ? [ depth - 1, 0 ].max : depth + 1
  end
end
