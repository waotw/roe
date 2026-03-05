class Admin::LayoutsController < Admin::BaseController
  LAYOUT_FILES = {
    'header' => Rails.root.join('content/layout/header.md'),
    'footer' => Rails.root.join('content/layout/footer.md')
  }

  def index
    @layouts = [
      { name: 'Header', file: 'header', path: admin_layout_header_edit_path },
      { name: 'Footer', file: 'footer', path: admin_layout_footer_edit_path }
    ]
  end

  def edit_header
    @layout_name = 'Header'
    @file_key = 'header'
    @content = File.read(LAYOUT_FILES['header'])
    render :edit
  end

  def edit_footer
    @layout_name = 'Footer'
    @file_key = 'footer'
    @content = File.read(LAYOUT_FILES['footer'])
    render :edit
  end

  def update_header
    File.write(LAYOUT_FILES['header'], params[:content].gsub(/\r\n/, "\n"))
    flash[:notice] = "Header updated"
    flash[:trigger_refresh] = true
    redirect_to admin_layout_header_edit_path
  end

  def update_footer
    File.write(LAYOUT_FILES['footer'], params[:content].gsub(/\r\n/, "\n"))
    flash[:notice] = "Footer updated"
    flash[:trigger_refresh] = true
    redirect_to admin_layout_footer_edit_path
  end
end
