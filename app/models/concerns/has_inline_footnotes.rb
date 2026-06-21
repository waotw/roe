module HasInlineFootnotes
  extend ActiveSupport::Concern

  private

  # The (*...*) inline footnote syntax has been retired in favour of
  # standard Kramdown footnotes ([^1] / [^1]:) and image captions
  # (![alt](/path.jpg)(*caption*)). This method is kept as a no-op so
  # existing include statements in models don't need to change.
  def process_inline_footnotes(markdown)
    markdown
  end
end
