class Admin::LayoutsController < Admin::BaseController
  LAYOUT_FILES = {
    'navigation' => Rails.root.join('site/layout/navigation.md'),
    'footer' => Rails.root.join('site/layout/footer.md')
  }

  def default_layout_content(file_key)
    author_name = SiteConfig.get('author_name').presence || SiteConfig.get('author').presence || 'Author Name'
    site_title = SiteConfig.get('title').presence || 'Site Title'
    site_url = SiteConfig.get('url').presence || '/'
    year = Date.current.year

    case file_key
    when 'navigation'
      <<~MD
        #{author_name}
        {: .site-author}

        [#{site_title}](#{site_url}){: .site-logo}

        [Home](#{site_url}) **|**

      MD
    when 'footer'
      <<~MD
        Built with [Roe](https://getroe.com) • © #{author_name} #{year}

      MD
    else
      "<!-- #{file_key.capitalize} content - edit as needed -->\n\n"
    end
  end

  before_action :ensure_layout_directory_exists
  before_action :ensure_layout_file_exists, only: [:edit_navigation, :edit_footer]

  def index
    @layouts = [
      { name: 'Navigation', file: 'navigation', path: admin_layout_navigation_edit_path, exists: File.exist?(LAYOUT_FILES['navigation']) },
      { name: 'Footer', file: 'footer', path: admin_layout_footer_edit_path, exists: File.exist?(LAYOUT_FILES['footer']) }
    ]
  end

  def edit_navigation
    @layout_name = 'Navigation'
    @file_key = 'navigation'
    @content = File.read(LAYOUT_FILES['navigation'])
    render :edit
  end

  def edit_footer
    @layout_name = 'Footer'
    @file_key = 'footer'
    @content = File.read(LAYOUT_FILES['footer'])
    render :edit
  end

  def update_navigation
    File.write(LAYOUT_FILES['navigation'], params[:content].gsub(/\r\n/, "\n"))
    flash[:notice] = "Navigation updated"
    flash[:trigger_refresh] = true
    redirect_to admin_layout_navigation_edit_path
  end

  def update_footer
    File.write(LAYOUT_FILES['footer'], params[:content].gsub(/\r\n/, "\n"))
    flash[:notice] = "Footer updated"
    flash[:trigger_refresh] = true
    redirect_to admin_layout_footer_edit_path
  end

  def generate_missing
    file_key = params[:file_key]
    unless LAYOUT_FILES.key?(file_key)
      flash[:alert] = "Invalid layout file"
      redirect_to admin_layouts_path and return
    end

    file_path = LAYOUT_FILES[file_key]
    if File.exist?(file_path)
      flash[:notice] = "#{file_key.capitalize} layout file already exists"
    else
      File.write(file_path, default_layout_content(file_key))
      flash[:notice] = "#{file_key.capitalize} layout file created successfully"
    end

    redirect_to send("admin_layout_#{file_key}_edit_path")
  end

  private

  def ensure_layout_directory_exists
    layout_dir = Rails.root.join('site/layout')
    unless File.directory?(layout_dir)
      flash[:alert] = "Layout directory is missing. Please create it manually at site/layout/"
      redirect_to admin_dashboard_path
    end
  end

  def ensure_layout_file_exists
    file_key = action_name == 'edit_navigation' ? 'navigation' : 'footer'
    file_path = LAYOUT_FILES[file_key]

    unless File.exist?(file_path)
      flash[:alert] = "#{file_key.capitalize} layout file is missing. <a href='#{generate_missing_admin_layouts_path(file_key: file_key)}' class='underline'>Click here to create it</a>".html_safe
      redirect_to admin_layouts_path
    end
  end
end
