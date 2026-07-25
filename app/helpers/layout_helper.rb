module LayoutHelper
  def render_layout_file(filename, current_page: nil)
    file_path = LayoutFiles.path(filename)

    return "" unless File.exist?(file_path)

    content = File.read(file_path)

    # Run through the full roe-anji pipeline (Collections, Cards, Galleries,
    # etc.), not raw Kramdown — that's how a collection in header.md or
    # footer.md renders. to_html handles inline-pipe escaping itself.
    html = LayoutMarkdown.render(content, static: @static_generation)

    # Add the active class to header/nav links (header supersedes the legacy
    # navigation file). Runs on the final HTML, so collection-generated nav
    # links get it too.
    if %w[header navigation].include?(filename.to_s)
      html = add_active_nav_class(html, current_page)
    end

    html.html_safe
  rescue => e
    Rails.logger.error "Error rendering layout file #{filename}: #{e.message}"
    ""
  end

  # Check if sidebar should be shown for current content
  def show_sidebar?
    return false unless File.exist?(sidebar_file_path)

    # Check post/page metadata for override
    content = @post || @page || @doc
    if content.respond_to?(:metadata)
      # If show_sidebar is explicitly false, hide it
      return false if content.metadata["show_sidebar"] == false
    end

    # Check sidebar scope from frontmatter
    scope = sidebar_scope
    return true if scope.include?("all")

    # Determine current content type
    current_type = if @post
      "posts"
    elsif @page
      "pages"
    elsif @doc
      "documentation"
    elsif @product
      "products"
    else
      "unknown"
    end

    scope.include?(current_type)
  end

  # Get sidebar position from frontmatter (default: left)
  def sidebar_position
    return @sidebar_position if defined?(@sidebar_position)

    @sidebar_position = parse_sidebar_frontmatter["position"] || "left"
  end

  # How the sidebar behaves on narrow screens (frontmatter `mobile:`):
  #   hidden (default) — hidden below the breakpoint
  #   top             — horizontal strip under the header, always visible
  #   bottom          — full-width below the content, always visible
  def sidebar_mobile
    return @sidebar_mobile if defined?(@sidebar_mobile)

    value = parse_sidebar_frontmatter["mobile"].to_s.strip.downcase
    @sidebar_mobile = %w[top bottom hidden].include?(value) ? value : "hidden"
  end

  # Optional override for a relocated sidebar menu's orientation on narrow
  # screens (frontmatter `mobile_style:`). Unset (nil) keeps the sensible
  # default: `mobile: top` flips the menu horizontal, `bottom` stays vertical.
  # Set `horizontal` or `vertical` to force it either way.
  def sidebar_mobile_style
    return @sidebar_mobile_style if defined?(@sidebar_mobile_style)

    value = parse_sidebar_frontmatter["mobile_style"].to_s.strip.downcase
    @sidebar_mobile_style = %w[horizontal vertical].include?(value) ? value : nil
  end

  # Get sidebar scope from frontmatter (default: ['all'])
  # Supports: 'all', 'pages', 'posts', 'products', 'documentation'
  # Can be a single value or array: 'pages, posts' or ['pages', 'posts']
  def sidebar_scope
    return @sidebar_scope if defined?(@sidebar_scope)

    scope_value = parse_sidebar_frontmatter["scope"] || "all"

    # Handle both string and array inputs
    @sidebar_scope = case scope_value
    when String
      # Split by comma and clean up whitespace
      scope_value.split(",").map(&:strip)
    when Array
      scope_value
    else
      [ "all" ]
    end
  end

  # Render sidebar with proper positioning class
  def render_sidebar
    return "" unless show_sidebar?

    file_path = sidebar_file_path
    content = File.read(file_path)

    # Parse out frontmatter if present (position/scope live there)
    body_content = extract_body_from_content(content)

    # Full roe-anji pipeline so Collections/Cards/Galleries work in the sidebar
    html = LayoutMarkdown.render(body_content, static: @static_generation)

    # Highlight the current page — a `menu` collection in the sidebar is
    # navigation just like the header, so it gets the same active-link pass.
    html = add_active_nav_class(html, @post || @page || @doc)

    html.html_safe
  rescue => e
    Rails.logger.error "Error rendering sidebar: #{e.message}"
    ""
  end

  private

  def sidebar_file_path
    File.join(RoeSitePaths::SITE_PATH, "layout", "sidebar.md")
  end

  def parse_sidebar_frontmatter
    return {} unless File.exist?(sidebar_file_path)

    content = File.read(sidebar_file_path)
    parse_frontmatter(content)
  rescue => e
    Rails.logger.error "Error parsing sidebar frontmatter: #{e.message}"
    {}
  end

  def parse_frontmatter(content)
    frontmatter = {}

    # Check for YAML frontmatter (--- at start)
    if content =~ /\A---\s*\n(.*?)^---\s*\n?/m
      yaml_content = $1
      frontmatter = YAML.safe_load(yaml_content) || {}
    end

    frontmatter
  rescue => e
    Rails.logger.error "Error parsing frontmatter: #{e.message}"
    {}
  end

  def extract_body_from_content(content)
    # Remove YAML frontmatter if present
    if content =~ /\A---\s*\n.*?^---\s*\n?/m
      content.sub(/\A---\s*\n.*?^---\s*\n?/m, "")
    else
      content
    end
  end

  def logo_classes
    logo_url = SiteConfig.get("logo")
    logo_style = SiteConfig.get("logo_style")
    has_logo = logo_url.present? && logo_url != "none"

    classes = []
    classes << "logo" if has_logo
    classes << "logo-#{logo_style}" if has_logo && logo_style.present?
    classes.join(" ")
  end

  private

  def add_active_nav_class(html, current_page)
    doc = Nokogiri::HTML::DocumentFragment.parse(html)

    # Get current URL name from the actual content object (not page number)
    current_url_name = if current_page.respond_to?(:url_name)
      current_page.url_name
    elsif defined?(@post) && @post&.respond_to?(:url_name)
      @post.url_name
    elsif defined?(@page) && @page&.respond_to?(:url_name)
      @page.url_name
    elsif defined?(@doc) && @doc&.respond_to?(:url_name)
      @doc.url_name
    end

    # Get current path, handling both dynamic requests and static generation
    current_path = begin
      request.path if defined?(request) && request.respond_to?(:path)
    rescue
      nil
    end

    doc.css("a").each do |link|
      href = link["href"]
      next unless href

      # Normalize href for comparison (remove leading slash and .html)
      normalized_href = href.sub(/^\.\.\//, "").sub(/^\.\//, "").sub(/^\//, "").sub(/\.html$/, "")

      # Handle root/home - href is '/' or empty
      if href == "/" || href == "./" || href.end_with?("index.html") || normalized_href.empty?
        if current_url_name == "home" || current_path == "/"
          add_active_class(link)
        end
        next
      end

      # Match other pages by url_name
      if normalized_href == current_url_name
        add_active_class(link)
      end
    end

    doc.to_html
  rescue => e
    Rails.logger.error "Error in add_active_nav_class: #{e.message}"
    html
  end

  def add_active_class(link)
    existing_class = link["class"].to_s
    link["class"] = existing_class.blank? ? "active" : "#{existing_class} active"
  end

  def escape_inline_pipes_for_layout(content)
      lines = content.split("\n")
      in_table = false

      lines.map.with_index do |line, i|
        next_line = i < lines.length - 1 ? lines[i + 1] : nil

        # Check if we're entering a table (next line is separator)
        if next_line && table_separator_line?(next_line)
          in_table = true
        end

        # Check if this is a separator line
        if table_separator_line?(line)
          in_table = true
          next line
        end

        # If in table and line starts with pipe, it's a table row
        if in_table && line.match?(/^\s*>?\s*\|/)
          next line
        end

        # If we were in a table but this line doesn't start with pipe, we've exited
        if in_table && !line.match?(/^\s*>?\s*\|/)
          in_table = false
        end

        # Not in table, escape pipes
        line.gsub(/\|/, "&#124;")
      end.join("\n")
    end

    def table_separator_line?(line)
      line.match?(/^\s*>?\s*\|?\s*:?-+:?\s*\|[\s\|:-]+$/)
    end
end
