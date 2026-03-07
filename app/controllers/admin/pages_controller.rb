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
    file_path = Rails.root.join("content/pages/#{filename}.md")

    if File.exist?(file_path)
      flash[:error] = "A page with that filename already exists"
      @template = params[:content]
      render :new
      return
    end

    # Load template and populate title from filename
    template_content = load_page_template
    title = filename_to_title(filename)

    # Parse template and update title
    parsed = FrontMatterParser::Parser.new(:md).call(template_content)
    metadata = parsed.front_matter.merge("title" => title)

    yaml_content = metadata.to_yaml.sub(/\A---\n/, '').strip
    content = "---\n#{yaml_content}\n---\n#{parsed.content}"

    normalize_and_write(file_path, content)

    # Manually sync the file immediately
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

    # Reconstruct full markdown file
    begin
      # Parse submitted metadata YAML
      metadata = YAML.safe_load(params[:metadata], permitted_classes: [ Date, Time, Symbol ])

      # Validate YAML structure
      unless metadata.is_a?(Hash)
        raise "Metadata must be key-value pairs"
      end

    rescue => e
      flash.now[:warning] = "YAML warning: #{e.message}. File saved anyway."
      # Save as-is even with invalid YAML - but wrap properly
      full_content = "---\n#{params[:metadata].strip}\n---\n#{params[:content]}"
      normalize_and_write(@page.file_path, full_content)

      @metadata = params[:metadata]
      @content = params[:content]
      @preview_path = preview_admin_page_path(@page)
      render :edit
      return
    end

    # Valid YAML - reconstruct properly
    yaml_content = metadata.to_yaml.sub(/\A---\n/, '').strip
    full_content = "---\n#{yaml_content}\n---\n#{params[:content]}"
    full_content = full_content.gsub(/\r\n/, "\n")
    normalize_and_write(@page.file_path, full_content)

    ContentSync.sync_file(@page.file_path)

    flash[:notice] = "Page saved"
    flash[:trigger_refresh] = true

    # Re-parse for display
    @metadata = yaml_content
    @content = params[:content]
    render :edit
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

  def preview
    # Reconstruct content from params
    metadata_yaml = params[:metadata]
    content = params[:content]

    begin
      metadata = YAML.safe_load(metadata_yaml, permitted_classes: [Date, Time, Symbol])
    rescue
      metadata = {}
    end

    # Create a temporary post object (not saved to DB)
    @page = Page.find(params[:id])

    # Override with preview content
    @page.define_singleton_method(:metadata) { metadata }
    @page.define_singleton_method(:content) { content }
    @page.define_singleton_method(:rendered_content) do
      MarkdownRenderer.render(content, metadata)
    end

    render template: 'pages/show', layout: 'site'
  end

  private

  def load_page_template
    template_path = Rails.root.join("content/templates/page_template.md")

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
