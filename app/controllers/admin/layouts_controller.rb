class Admin::LayoutsController < Admin::BaseController
  def default_layout_content(file_key)
    author_name = SiteConfig.get("author_name").presence || SiteConfig.get("author").presence || "Author Name"
    site_title = SiteConfig.get("title").presence || "Site Title"
    site_url = SiteConfig.get("url").presence || "/"
    year = Date.current.year

    case file_key
    when "header"
      <<~MD
        #{author_name}
        {: .site-author}

        [#{site_title}](#{site_url}){: .site-logo}

        [Home](#{site_url}) **|**

      MD
    when "footer"
      <<~MD
        Built with [Roe](https://getroe.com) • © #{author_name} #{year}

      MD
    when "sidebar"
      <<~MD
        ---
        position: left
        scope: pages
        ---

        ## Sidebar

        This content appears in the sidebar.

        - [Link 1](#)
        - [Link 2](#)
        - [Link 3](#)

      MD
    else
      "<!-- #{file_key.capitalize} content - edit as needed -->\n\n"
    end
  end

  before_action :ensure_layout_directory_exists
  before_action :ensure_layout_file_exists, only: [ :edit_header, :edit_footer, :edit_sidebar ]

  def index
    @layouts = [
      { name: "Header", file: "header", path: admin_layout_header_edit_path, exists: LayoutFiles.exist?("header") },
      { name: "Footer", file: "footer", path: admin_layout_footer_edit_path, exists: LayoutFiles.exist?("footer") },
      { name: "Sidebar", file: "sidebar", path: admin_layout_sidebar_edit_path, exists: LayoutFiles.exist?("sidebar") }
    ]
  end

  def edit_header
    @layout_name = "Header"
    @file_key = "header"
    @content = File.read(LayoutFiles.path("header"))
    render :edit
  end

  def edit_footer
    @layout_name = "Footer"
    @file_key = "footer"
    @content = File.read(LayoutFiles.path("footer"))
    render :edit
  end

  def edit_sidebar
    @layout_name = "Sidebar"
    @file_key = "sidebar"
    @content = File.read(LayoutFiles.path("sidebar"))
    render :edit
  end

  def update_header
    File.write(LayoutFiles.path("header"), params[:content].gsub(/\r\n/, "\n"))
    flash[:notice] = "Header updated"
    flash[:trigger_refresh] = true
    redirect_to admin_layout_header_edit_path
  end

  def update_footer
    File.write(LayoutFiles.path("footer"), params[:content].gsub(/\r\n/, "\n"))
    flash[:notice] = "Footer updated"
    flash[:trigger_refresh] = true
    redirect_to admin_layout_footer_edit_path
  end

  def update_sidebar
    File.write(LayoutFiles.path("sidebar"), params[:content].gsub(/\r\n/, "\n"))
    flash[:notice] = "Sidebar updated"
    flash[:trigger_refresh] = true
    redirect_to admin_layout_sidebar_edit_path
  end

  # Only the sidebar is optional. Header and footer ship with every site so
  # they have no destroy action — re-enable here only if that ever changes.
  def destroy_sidebar
    file_path = LayoutFiles.path("sidebar")
    if File.exist?(file_path)
      File.delete(file_path)
      flash[:notice] = "Sidebar deleted"
      flash[:trigger_refresh] = true
    else
      flash[:alert] = "Sidebar file was already gone"
    end
    redirect_to admin_layouts_path
  end

  def generate_missing
    file_key = params[:file_key]
    unless LayoutFiles::KEYS.include?(file_key)
      flash[:alert] = "Invalid layout file"
      redirect_to admin_layouts_path and return
    end

    file_path = LayoutFiles.path(file_key)
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
    layout_dir = File.join(RoeSitePaths::SITE_PATH, "layout")
    unless File.directory?(layout_dir)
      flash[:alert] = "Layout directory is missing. Please create it manually at site/layout/"
      redirect_to admin_dashboard_path
    end
  end

  def ensure_layout_file_exists
    file_key = action_name.to_s.sub(/\A(edit|update)_/, "")

    unless LayoutFiles.exist?(file_key)
      flash[:alert] = "#{file_key.capitalize} layout file is missing. <a href='#{generate_missing_admin_layouts_path(file_key: file_key)}' class='underline'>Click here to create it</a>".html_safe
      redirect_to admin_layouts_path
    end
  end
end
