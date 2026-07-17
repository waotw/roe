# Renders layout files (navigation, footer, sidebar) through the full roe-anji
# pipeline, so Collections, Cards, Galleries, and the rest work in layout areas
# — not just plain Kramdown. Layout files aren't ActiveRecord records, so this
# small object supplies the minimal surface HasMarkdownExtensions#to_html needs:
# `content` (the body) plus `metadata`/`url_name` (used only when a collection
# in a layout uses `related: true`).
class LayoutMarkdown
  include HasMarkdownExtensions

  attr_reader :content, :metadata

  def initialize(content, metadata = {})
    @content = content.to_s
    @metadata = metadata || {}
  end

  # Layout files have no canonical URL of their own.
  def url_name
    nil
  end

  def self.render(content, static: false)
    new(content).to_html(static: static)
  end
end
