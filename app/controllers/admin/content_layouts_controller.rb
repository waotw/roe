# Content layouts in the admin: the Content section of the Layouts page.
#
# Every type is editable straight away. A type on the default opens Roe's
# copy; saving writes site/layout/content/<name>.yml, a custom layout from
# then on. "Use default" deletes the custom file, so the type goes back to
# Roe's and picks up its improvements in updates.
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
    @sidebar_position = sidebar_position_for(@name)
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
      redirect_to admin_edit_content_layout_path(@name), notice: "#{@name.humanize} is back on the default layout"
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

  # No comments in the file (AGENTS.md rule 5): the editor's side panel
  # explains the format.
  NEW_LAYOUT = <<~YAML.freeze
    - title
    - body
  YAML

  private

  # Where the sidebar sits around this layout's content ("left" or "right"),
  # or nil when it doesn't show for this type — the editor draws the site's
  # header, sidebar and footer around the textarea so it reads as the middle
  # of a page. An extra layout can be used by any type, so it shows the
  # sidebar if the sidebar covers any type. A record's own show_sidebar can
  # still differ; this is the usual case.
  def sidebar_position_for(name)
    covered =
      case name
      when *Post::POST_TYPES.keys.map(&:to_s)   then Sidebar.covers?("posts")
      when "page", "podcast-page", "music-page" then Sidebar.covers?("pages")
      when "product"                            then Sidebar.covers?("products")
      when "documentation"                      then Sidebar.covers?("documentation")
      else Sidebar::TYPES.any? { |type| Sidebar.covers?(type) }
      end
    return nil unless covered

    Sidebar.frontmatter["position"].to_s.strip == "right" ? "right" : "left"
  end

  def set_name
    @name = params[:name].to_s
    head :not_found unless @name.match?(ContentLayout::NAME_RE)
  end
end
