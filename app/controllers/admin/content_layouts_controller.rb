# Content layouts in the admin: the Content section of the Layouts page.
#
# Every type is editable straight away. A type still on Roe's default opens
# Roe's copy; saving writes site/layout/content/<name>.yml, which from then on
# is the site's. "Use Roe's default" deletes the site's copy, so the type goes
# back to Roe's and picks up its improvements in updates.
#
# Extra layouts (New layout) are picked per post with `layout: <name>`.
class Admin::ContentLayoutsController < Admin::BaseController
  before_action :set_name, only: [ :edit, :update, :destroy ]

  def edit
    site_path = ContentLayout.site_path(@name)
    roe_path = ContentLayout.roe_default_path(@name)
    unless File.file?(site_path) || File.file?(roe_path)
      redirect_to admin_layouts_path, alert: "There's no layout called #{@name}."
      return
    end

    @customised = File.file?(site_path)
    @roe_default = File.file?(roe_path)
    @content = File.read(@customised ? site_path : roe_path)
    @warnings = ContentLayout.parse(@name, @content).warnings
  end

  def update
    content = params[:content].to_s.gsub("\r\n", "\n")
    FileUtils.mkdir_p(ContentLayout::SITE_DIR)
    File.write(ContentLayout.site_path(@name), content)

    warnings = ContentLayout.parse(@name, content).warnings
    flash[:notice] = "#{@name.humanize} layout saved"
    flash[:alert] = warnings.join(" ") if warnings.any?
    redirect_to admin_edit_content_layout_path(@name)
  end

  # A type's layout goes back to Roe's default; an extra layout is deleted.
  def destroy
    path = ContentLayout.site_path(@name)
    File.delete(path) if File.file?(path)

    if File.file?(ContentLayout.roe_default_path(@name))
      redirect_to admin_edit_content_layout_path(@name), notice: "#{@name.humanize} is back on Roe's default layout"
    else
      redirect_to admin_layouts_path, notice: "#{@name} layout deleted"
    end
  end

  def create
    name = params[:name].to_s.strip.downcase.tr(" ", "-")

    if !name.match?(ContentLayout::NAME_RE)
      redirect_to admin_layouts_path, alert: "A layout name is lowercase letters, numbers, - and _."
    elsif File.file?(ContentLayout.site_path(name)) || File.file?(ContentLayout.roe_default_path(name))
      redirect_to admin_layouts_path, alert: "There's already a layout called #{name}."
    else
      FileUtils.mkdir_p(ContentLayout::SITE_DIR)
      File.write(ContentLayout.site_path(name), NEW_LAYOUT)
      redirect_to admin_edit_content_layout_path(name), notice: "Layout created. Use it on a post with layout: #{name}"
    end
  end

  # COPY: placeholder wording — owner will rewrite
  NEW_LAYOUT = <<~YAML.freeze
    # Use this layout on a post by adding `layout: <name>` to its metadata.
    # One part per line. [a, b] puts parts in one group, styled together.

    - title
    - body
  YAML

  private

  def set_name
    @name = params[:name].to_s
    head :not_found unless @name.match?(ContentLayout::NAME_RE)
  end
end
