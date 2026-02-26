module LayoutHelper
  def render_layout_file(filename)
    file_path = Rails.root.join('content', 'layout', "#{filename}.md")

    return '' unless File.exist?(file_path)

    content = File.read(file_path)
    Kramdown::Document.new(content).to_html.html_safe
  rescue => e
    Rails.logger.error "Error rendering layout file #{filename}: #{e.message}"
    ''
  end
end
