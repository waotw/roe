# Keeps French-style punctuation on the same line as the word before it.
#
# French puts a space before ? ! : ; » and after «. Written as an ordinary
# space, a browser may break the line there and leave the ? alone at the
# start of the next one. This swaps those spaces for a no-break space
# (U+00A0) in rendered HTML. It's the width of a normal space, so nothing
# looks different; the line just can't break there. Files aren't changed.
#
# English rarely puts a space before these marks, so English text is
# untouched in practice.
#
# Only text is changed: tags and their attributes (links, image addresses)
# are left alone, and so is everything inside <pre>, <code>, <kbd>, <samp>,
# <script>, <style> and <textarea>, so code examples stay exact.
module PunctuationSpaces
  NBSP = "\u00A0".freeze

  SKIP = %w[pre code kbd samp script style textarea].freeze
  TAG = /(<!--.*?-->|<[^>]*>)/m

  # Spaces (and existing no-break spaces) before the closing marks, and after
  # the opening guillemet. Entities cover kramdown's typographic output.
  BEFORE = /[ \u00A0]+(?=[?!:;»]|&raquo;|&#187;)/
  AFTER = /(«|&laquo;|&#171;)[ \u00A0]+/

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
        part.gsub(BEFORE, NBSP).gsub(AFTER) { "#{Regexp.last_match(1)}#{NBSP}" }
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
