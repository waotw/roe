# Markdown in a metadata value: a subtitle, an excerpt, a product's
# description, or any field a layout shows as a box (`pullquote:`).
#
# Inline formatting only — bold, italic, links, code — inside whatever element
# the page already wraps the value in, so a value never changes the markup
# around it: `<p class="post-subtitle">` stays one <p>, and so do a layout
# field's `<p class="post-field post-field-pullquote">` and a card's
# `<p class="card-excerpt">`.
#
# - Each line is its own line: line breaks become <br>, whatever the site's
#   `soft_line_breaks` setting, because a break written in a short value is
#   meant. Blank lines are dropped (a <p> can't hold another <p>).
# - A line can't start a list, heading, quote or code block: `- benjamin`
#   is text, not a bullet. Lines are rendered one at a time, so emphasis
#   can't run from one line onto the next.
# - Typography follows the body: straight quotes curl, `...` becomes `…`.
# - GFM, as image captions use, so `snake_case` and bare URLs stay as written.
#
# `plain` is the same text with the Markdown taken out, for places that hold
# text rather than HTML: meta tags, feed descriptions, Snipcart's cart line,
# the search index.
class FieldText
  CACHE_LIMIT = 5_000

  @cache = {}
  @lock = Mutex.new

  class << self
    # HTML-safe inline markup. Empty string when there's nothing to show.
    # A value that's already HTML-safe (from `shortened`) is used as it is.
    def html(value)
      return value if value.is_a?(ActiveSupport::SafeBuffer)

      text = normalize(value)
      return "".html_safe if text.empty?

      cached(text) { render(text) }.html_safe
    end

    # The text a reader sees, without markup. Line breaks become `separator`.
    def plain(value, separator: " ")
      text = normalize(value)
      return "" if text.empty?

      # The only line breaks in the HTML are the ones after each <br>.
      fragment = Nokogiri::HTML::DocumentFragment.parse(html(text).to_str.delete("\n"))
      fragment.css("br").each { |br| br.replace(Nokogiri::XML::Text.new(separator, fragment.document)) }
      fragment.text.strip
    end

    # The value, or — when what a reader sees is longer than `max_length` —
    # that text cut to fit, ending "...", as escaped HTML. Cutting the
    # Markdown itself could split a `*pair*` and show a stray asterisk, so a
    # shortened value loses its formatting; `html` uses it as it is.
    def shortened(value, max_length)
      text = plain(value)
      return value if text.length <= max_length

      ERB::Util.html_escape(text[0..max_length - 3] + "...")
    end

    private

    def normalize(value)
      value = value.join(", ") if value.is_a?(Array)
      value.to_s.gsub(/\r\n?/, "\n").strip
    end

    def render(text)
      text.split("\n").map(&:strip).reject(&:empty?).map { |line| line_html(line) }.join("<br>\n")
    end

    # A line that kramdown would read as a block (a list item, a heading, a
    # quote, a rule, a link definition) gets its first character as an
    # entity, so it reads as text; failing that, it's shown as written.
    def line_html(line)
      inline(line) || inline("&##{line.ord};#{line[1..]}") || ERB::Util.html_escape(line).to_s
    end

    def inline(line)
      html = Kramdown::Document.new(line, input: "GFM", hard_wrap: false).to_html.strip
      match = html.match(%r{\A<p>(.*)</p>\z}m)
      match && !match[1].include?("<p>") ? match[1] : nil
    rescue StandardError
      nil
    end

    def cached(text)
      @lock.synchronize do
        return @cache[text] if @cache.key?(text)
      end
      result = yield
      @lock.synchronize do
        @cache.clear if @cache.size >= CACHE_LIMIT
        @cache[text] = result
      end
    end
  end
end
