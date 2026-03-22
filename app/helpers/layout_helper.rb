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

  def logo_classes
    logo_url = SiteConfig.get('logo')
    logo_style = SiteConfig.get('logo_style')
    has_logo = logo_url.present? && logo_url != 'none'

    classes = []
    classes << 'logo' if has_logo
    classes << "logo-#{logo_style}" if has_logo && logo_style.present?
    classes.join(' ')
  end

  private

  def add_active_nav_class(html, current_page)
    doc = Nokogiri::HTML::DocumentFragment.parse(html)

    # Get current URL name from the actual content object (not page number)
    current_url_name = if current_page.respond_to?(:url_name)
      current_page.url_name
    elsif @post&.respond_to?(:url_name)
      @post.url_name
    elsif @page&.respond_to?(:url_name)
      @page.url_name
    elsif @doc&.respond_to?(:url_name)
      @doc.url_name
    end

    current_path = request.path rescue nil  # Add rescue in case request doesn't exist

    doc.css('a').each do |link|
      href = link['href']
      next unless href

      link_path = href.sub(/^\//, '')

      # Handle root/home - check for both dynamic (/) and static (empty or 'home')
      if href == '/' && (current_path == '/' || current_path.blank? || current_url_name == 'home')
        add_active_class(link)
        next
      end

      next if href == '/'

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
