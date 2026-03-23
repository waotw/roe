class Admin::LayoutsController < Admin::BaseController
  LAYOUT_FILES = {
    'navigation' => Rails.root.join('site/layout/navigation.md'),
    'footer' => Rails.root.join('site/layout/footer.md')
  }

  def index
    @layouts = [
      { name: 'Navigation', file: 'navigation', path: admin_layout_navigation_edit_path },
      { name: 'Footer', file: 'footer', path: admin_layout_footer_edit_path }
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
end
