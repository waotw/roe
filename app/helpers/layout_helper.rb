module LayoutHelper
  def render_layout_file(filename, current_page: nil)
    file_path = Rails.root.join('site', 'layout', "#{filename}.md")

    return '' unless File.exist?(file_path)

    content = File.read(file_path)
    html = Kramdown::Document.new(content).to_html

    # Add active class to navigation links if this is the navigation file
    if filename == 'navigation'
      html = add_active_nav_class(html, current_page)
    end

    html.html_safe
  rescue => e
    Rails.logger.error "Error rendering layout file #{filename}: #{e.message}"
    ''
  end

  private

  def add_active_nav_class(html, current_page)
    doc = Nokogiri::HTML::DocumentFragment.parse(html)
    current_url_name = current_page&.url_name
    current_path = request.path # Get current path from controller context

    doc.css('a').each do |link|
      href = link['href']
      next unless href

      # Remove leading slash from href for comparison
      link_path = href.sub(/^\//, '')

      # Handle root path - match only when both are exactly '/'
      if href == '/' && current_path == '/'
        add_active_class(link)
        next
      end

      # Skip root link when not on root
      next if href == '/'

      # Direct comparison with current page's url_name
      if link_path == current_url_name
        add_active_class(link)
      end
    end

    doc.to_html
  rescue => e
    Rails.logger.error "Error in add_active_nav_class: #{e.message}"
    html
  end

  def add_active_class(link)
    existing_class = link['class'].to_s
    link['class'] = existing_class.blank? ? 'active' : "#{existing_class} active"
  end
end
