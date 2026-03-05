module HasInlineFootnotes
  extend ActiveSupport::Concern

  private

  def process_inline_footnotes(markdown)
    footnote_counter = 0
    footnotes = []

    # Match (*...*) or (*[marker] ...*)
    processed = markdown.gsub(/\(\*(\[([^\]]+)\]\s*)?([^)]*)\*\)/) do
      marker = $2
      content = $3.strip

      if marker
        # Custom marker: (*[source] Author Name*)
        footnotes << "[^#{marker}]: #{content}"
        "[^#{marker}]"
      else
        # Auto-numbered: (*This is a footnote*)
        footnote_counter += 1
        footnotes << "[^#{footnote_counter}]: #{content}"
        "[^#{footnote_counter}]"
      end
    end

    # Append footnote definitions at end if any were found
    if footnotes.any?
      processed + "\n\n" + footnotes.join("\n")
    else
      processed
    end
  end
end
