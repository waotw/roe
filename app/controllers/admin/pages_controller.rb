class Admin::PagesController < Admin::BaseController
  def index
    @pages = Page.order(:created_at)
    @title = "Pages"
    @description = "All pages on your site."
  end

  def new
    @template = load_page_template
  end

  def create
    filename = sanitize_filename(params[:filename])
    file_path = Rails.root.join("site/pages/#{filename}.md")

    if File.exist?(file_path)
      flash.now[:error] = "A page with that filename already exists"
      @template = params[:content]
      @filename = filename
      render :new, status: :unprocessable_entity
      return
    end

    template_content = load_page_template
    title = filename_to_title(filename)

    parsed = FrontMatterParser::Parser.new(:md).call(template_content)
    metadata = parsed.front_matter.merge("title" => title)

    # Use formatted YAML
    yaml_content = Page.format_metadata_yaml(metadata)
    content = "---\n#{yaml_content}\n---\n#{parsed.content}"

    normalize_and_write(file_path, content)
    ContentSync.sync_file(file_path)

    page = Page.find_by(file_path: file_path.to_s)

    if page
      redirect_to edit_admin_page_path(page)
    else
      flash[:error] = "Page file created but failed to sync to database"
      redirect_to admin_pages_path
    end
  end

  def edit
    @page = Page.find(params[:id])
    raw_content = File.read(@page.file_path)

    parsed = FrontMatterParser::Parser.new(:md).call(raw_content)

    # Convert hash to YAML without document separator
    @metadata = parsed.front_matter.to_yaml.sub(/\A---\n/, '')
    @content = parsed.content
    @preview_path = preview_admin_page_path(@page)
  end

  def update
    @page = Page.find(params[:id])

    metadata_yaml = params[:metadata_final].presence || params[:metadata]

    begin
      # Validate it's valid YAML
      metadata = YAML.safe_load(metadata_yaml, permitted_classes: [ Date, Time, Symbol ])

      unless metadata.is_a?(Hash)
        raise "Metadata must be key-value pairs"
      end

    rescue => e
      flash[:warning] = "YAML warning: #{e.message}. File saved anyway."
      full_content = "---\n#{metadata_yaml}\n---\n#{params[:content]}"
      normalize_and_write(@page.file_path, full_content)
      redirect_to edit_admin_page_path(@page)
      return
    end

    # Use the original YAML string (preserves formatting from JavaScript)
    yaml_content = metadata_yaml.strip
    full_content = "---\n#{yaml_content}\n---\n#{params[:content]}"
    normalize_and_write(@page.file_path, full_content)

    ContentSync.sync_file(@page.file_path)

    flash[:notice] = "Page saved"

    redirect_to edit_admin_page_path(@page)
  end

  def rename
    @page = Page.find(params[:id])
    new_filename = sanitize_filename(params[:new_filename])

    if new_filename.blank?
      flash[:error] = "Filename cannot be empty"
      redirect_to admin_pages_path and return
    end

    old_path = Pathname.new(@page.file_path)
    new_path = old_path.dirname.join("#{new_filename}.md")

    if File.exist?(new_path) && new_path != old_path
      flash[:error] = "A file with that name already exists"
      redirect_to admin_pages_path and return
    end

    begin
      File.rename(old_path, new_path)
      @page.update(file_path: new_path.to_s)
      ContentSync.sync_file(new_path)

      flash[:notice] = "Renamed to #{new_filename}.md"
    rescue => e
      flash[:error] = "Failed to rename: #{e.message}"
    end

    redirect_to admin_pages_path
  end

  def publish
    @page = Page.find(params[:id])
    update_page_status(@page, 'published')
    flash[:notice] = "Page published"
    redirect_to edit_admin_page_path(@page)
  end

  def unpublish
    @page = Page.find(params[:id])
    update_page_status(@page, 'draft')
    flash[:notice] = "Page unpublished"
    redirect_to edit_admin_page_path(@page)
  end

  def destroy
    @page = Page.find(params[:id])
    file_path = @page.file_path

    begin
      # Delete the file from site/pages/
      File.delete(file_path) if File.exist?(file_path)

      # Delete the database record
      @page.destroy

      flash[:notice] = "Page deleted successfully"
    rescue => e
      flash[:error] = "Failed to delete page: #{e.message}"
    end

    redirect_to admin_pages_path
  end

  def preview
    @page = Page.find(params[:id])

    # POST = live editing preview with unsaved content
    if request.post?
      metadata_yaml = params[:metadata]
      content = params[:content]

      begin
        metadata = YAML.safe_load(metadata_yaml, permitted_classes: [ Date, Time, Symbol ]) || {}
      rescue
        metadata = {}
      end

      # Preserve url_name from database if not in submitted metadata
      metadata['url_name'] ||= @page.metadata['url_name']

      @page.metadata = metadata
      @page.content = content
    end
    # GET = show saved version from database

    # ALWAYS set preview mode
    @preview_mode = true
    @preview_id = "page-#{@page.id}"

    render template: 'pages/show', layout: 'site'
  end

  # def preview
  #   # Reconstruct content from params
  #   metadata_yaml = params[:metadata]
  #   content = params[:content]

  #   begin
  #     metadata = YAML.safe_load(metadata_yaml, permitted_classes: [ Date, Time, Symbol ])
  #   rescue
  #     metadata = {}
  #   end

  #   # Create a temporary page object (not saved to DB)
  #   @page = Page.find(params[:id])

  #   # Override with preview content
  #   @page.define_singleton_method(:metadata) { metadata }
  #   @page.define_singleton_method(:content) { content }
  #   @page.define_singleton_method(:rendered_content) do
  #     MarkdownRenderer.render(content, metadata)
  #   end

  #   @preview_mode = true  # Add this line

  #   render template: 'pages/show', layout: 'site'
  # end

  private

  def sanitize_filename(filename)
    filename = filename.to_s.sub(/\.md$/, '')
    filename = File.basename(filename)
    filename.gsub(/[^a-zA-Z0-9\-_]/, '-')
            .gsub(/-+/, '-')
            .strip
            .gsub(/^-|-$/, '')
  end

  def load_page_template
    template_path = Rails.root.join("site/templates/page_template.md")

    if File.exist?(template_path)
      File.read(template_path)
    else
      default_template
    end
  end

  def default_template
    <<~TEMPLATE
      ---
      title:
      status: draft
      ---

      Start writing...
    TEMPLATE
  end

  def filename_to_title(filename)
    name = filename.sub(/\.md$/, "")

    if name.match?(/[-_]/)
      name.split(/[-_]/).map(&:capitalize).join(' ')
    else
      name
    end
  end

  def sanitize_filename(filename)
    filename = filename.sub(/\.md$/, '')
    File.basename(filename)
  end

  def update_page_status(page, new_status)
    content = File.read(page.file_path)
    parsed = FrontMatterParser::Parser.new(:md).call(content)

    metadata = parsed.front_matter.merge("status" => new_status)
    yaml_content = metadata.to_yaml.sub(/\A---\n/, '').strip
    new_content = "---\n#{yaml_content}\n---\n#{parsed.content}"

    normalize_and_write(page.file_path, new_content)
    ContentSync.sync_file(page.file_path)
  end

  def normalize_and_write(file_path, content)
    normalized = content.gsub(/\r\n/, "\n")
    File.write(file_path, normalized)
  end
end
