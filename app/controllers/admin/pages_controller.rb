class Admin::PagesController < Admin::BaseController
  include BulkContentActions
  include CreatesContent

  def bulk_model = Page
  def bulk_index_path = admin_pages_path
  def bulk_label = "page"
  layout -> { action_name == "edit" ? "editor" : "admin" }

  def index
    # Default order: follow layout/navigation.md when it exists (pages listed in
    # the nav come first, in nav order); otherwise alphabetical by title. Pages
    # not in the nav fall to the end, alphabetically.
    @member_pages, @content_pages = ordered_pages.partition { |page| member_page?(page) }

    # Empty on a healthy site. Non-empty means Members is on and a page it needs
    # can't be found by declaration, by the form it renders, or by filename —
    # which is a broken site, not a preference.
    @missing_member_pages = MemberPages.missing

    # Working, but through a page that merely happens to carry the form. Roe
    # expects a dedicated page — it's the thing least likely to move — so this
    # is worth saying even though nothing is broken.
    @guessed_member_pages = MemberPages.guessed

    @title = "Pages"
    @description = "All pages on your site."
  end

  # Put back the member pages Roe ships, for a site missing one.
  #
  # The loader is skip-if-exists, so this only ever writes files that aren't
  # there — a customised sign-in page is never overwritten by the stock one.
  # That's what makes this safe to offer as a button rather than a warning
  # about a destructive action.
  def restore_member_pages
    # Both states are restorable, and only checking `missing` was a bug: a site
    # working through an incidental form has nothing missing, so the button
    # reported "nothing to restore" while the warning it sat under stayed up.
    missing = MemberPages.missing
    guessed = MemberPages.guessed.keys

    if missing.empty? && guessed.empty?
      redirect_to admin_pages_path, notice: "Nothing to restore — every member page Roe needs is already there."
      return
    end

    result = SiteTemplates::Loader.install(
      folder: "features/members", destination: RoeSitePaths::SITE_PATH
    )
    installed = Array(result[:installed])
    ContentSync.sync_all

    if installed.any?
      redirect_to admin_pages_path,
                  notice: "Restored #{installed.size} member #{"file".pluralize(installed.size)}."
    else
      stems = (missing + guessed).uniq
      redirect_to admin_pages_path,
                  alert: "Couldn't restore #{"the page".pluralize(stems.size)} for #{stems.join(', ')}. " \
                         "#{"It".pluralize(stems.size)} may need creating by hand — add `page_type:` so Roe can find #{stems.size == 1 ? "it" : "them"}."
    end
  rescue StandardError => e
    Rails.logger.error "[Admin::PagesController] restore_member_pages failed: #{e.class} #{e.message}"
    redirect_to admin_pages_path, alert: "Restore failed: #{e.message}"
  end

  def new
    @template = ContentTemplate.template_content("page")
  end

  def create
    title_param = params[:title].to_s.strip
    filename = sanitize_filename(params[:filename])

    # The two derive from each other: a filename gives a title, a title gives a
    # filename. Without this a title-only submission wrote "pages/.md", which
    # File.extname reads as having no extension — the front matter parser then
    # can't pick a syntax and dies on nil.to_sym.
    filename = sanitize_filename(title_param.parameterize) if filename.blank?

    if filename.blank?
      flash.now[:error] = "Give the page a filename or a title"
      render :new, status: :unprocessable_entity
      return
    end

    file_path = File.join(RoeSitePaths::SITE_PATH, "pages/#{filename}.md")

    if File.exist?(file_path)
      flash.now[:error] = "A page with that filename already exists"
      @template = params[:content]
      @filename = filename
      render :new, status: :unprocessable_entity
      return
    end

    title = title_param.presence || filename_to_title(filename)
    overrides = { "title" => title }.merge(create_field_overrides("page"))
    metadata, body = ContentTemplate.frontmatter_for("page", overrides)

    # Use formatted YAML
    yaml_content = Page.format_metadata_yaml(metadata)
    content = "---\n#{yaml_content}\n---\n#{body}"

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
    @metadata = parsed.front_matter.to_yaml.sub(/\A---\n/, "")
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

      # Handle tags (defensive — pages don't surface tags in the editor
      # by default, but a user could add the field via the Add Field menu
      # or in RAW YAML).
      if metadata["tags"].is_a?(String)
        if metadata["tags"].strip.empty? || metadata["tags"] == "[]"
          metadata["tags"] = []
        else
          metadata["tags"] = metadata["tags"].split(",").map(&:strip).reject(&:empty?)
        end
      elsif metadata["tags"].nil?
        metadata["tags"] = []
      end

      # Re-serialize via Page.format_metadata_yaml so pages produce the
      # same predictable file format as posts and products (always-quoted
      # strings, flow-style arrays). Inherited from HasMetadata.
      yaml_content = Page.format_metadata_yaml(metadata)

    rescue => e
      flash[:warning] = "YAML warning: #{e.message}. File saved anyway."
      full_content = "---\n#{metadata_yaml}\n---\n#{params[:content]}"
      normalize_and_write(@page.file_path, full_content)
      redirect_to edit_admin_page_path(@page)
      return
    end

    # Capture pre-save state to detect a publishing transition for flash text.
    was_published = @page.published?

    full_content = "---\n#{yaml_content}\n---\n#{params[:content]}"
    normalize_and_write(@page.file_path, full_content)

    ContentSync.sync_file(@page.file_path)
    @page.reload

    flash[:notice] = (!was_published && @page.published?) ? "Page published" : "Page saved"

    redirect_to edit_admin_page_path(@page)
  end

  # Copy a page's file into a numbered sibling — "-N" on the filename, " N" on
  # the title (from 2, skipping any that exist). Redirects into the new copy.
  def duplicate
    @page = Page.find(params[:id])
    raw = File.read(@page.file_path)
    parsed = FrontMatterParser::Parser.new(:md).call(raw)
    metadata = parsed.front_matter

    dir = Pathname.new(@page.file_path).dirname
    base_name = File.basename(@page.file_path, ".md").sub(/-\d+\z/, "")
    base_title = metadata["title"].to_s.sub(/\s+\d+\z/, "").strip

    n = 2
    n += 1 while File.exist?(dir.join("#{base_name}-#{n}.md"))
    new_path = dir.join("#{base_name}-#{n}.md")

    metadata["title"] = base_title.present? ? "#{base_title} #{n}" : "Untitled #{n}"
    yaml_content = Page.format_metadata_yaml(metadata)
    normalize_and_write(new_path, "---\n#{yaml_content}\n---\n#{parsed.content}")
    ContentSync.sync_file(new_path)

    new_page = Page.find_by(file_path: new_path.to_s)
    if new_page
      redirect_to edit_admin_page_path(new_page), notice: "Page duplicated"
    else
      redirect_to admin_pages_path, alert: "Duplicated the file but couldn't load the new page."
    end
  end

  def rename
    @page = Page.find(params[:id])
    new_filename = sanitize_filename(params[:new_filename])

    # Return to wherever rename was submitted from (editor stays on the editor,
    # index on the index); only same-site absolute paths are honored.
    return_to = lambda do
      target = params[:return_to].to_s
      safe = target.start_with?("/") && !target.start_with?("//")
      redirect_to(safe ? target : admin_pages_path, allow_other_host: false)
    end

    if new_filename.blank?
      flash[:error] = "Filename cannot be empty"
      return_to.call and return
    end

    old_path = Pathname.new(@page.file_path)
    new_path = old_path.dirname.join("#{new_filename}.md")

    if File.exist?(new_path) && new_path != old_path
      flash[:error] = "A file with that name already exists"
      return_to.call and return
    end

    begin
      File.rename(old_path, new_path)
      @page.update(file_path: new_path.to_s)
      ContentSync.sync_file(new_path)

      flash[:notice] = "Renamed to #{new_filename}.md"
    rescue => e
      flash[:error] = "Failed to rename: #{e.message}"
    end

    return_to.call
  end

  def publish_modal
    @page = Page.find(params[:id])

    # Swap in submitted form-state metadata so the modal reflects what's
    # *about to be saved* (e.g. just-changed audience), not the file.
    if params[:metadata].present?
      begin
        submitted = YAML.safe_load(params[:metadata], permitted_classes: [ Date, Time, Symbol ])
        @page.metadata = submitted if submitted.is_a?(Hash) && submitted.any?
      rescue => e
        Rails.logger.warn "publish_modal: ignoring unparseable submitted metadata (#{e.message})"
      end
    end

    @missing_requirements = build_publish_requirements(@page)
    @resource_label = "Page"
    @show_postmark_warning = false  # pages don't go to newsletter
    @paired_duration_for = nil       # no audio/video pairing for pages

    render partial: "admin/posts/publish_modal", layout: false
  end

  def unpublish
    @page = Page.find(params[:id])
    update_page_status(@page, "draft")
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
      metadata["url_name"] ||= @page.metadata["url_name"]

      @page.metadata = metadata
      @page.content = content
    end
    # GET = show saved version from database

    # ALWAYS set preview mode
    @preview_mode = true
    @preview_id = "page-#{@page.id}"

    render template: "pages/show", layout: "site"
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

  # Sets the status Roe ships on pages that lost theirs. Narrow by design —
  # see PageStatusRepair. Surfaced from the dashboard rather than run on boot,
  # so nobody's files change without them asking.
  def repair_statuses
    repaired = PageStatusRepair.repair!

    flash[:notice] = if repaired.any?
      "Repaired #{helpers.pluralize(repaired.size, 'page')}. They're reachable again."
    else
      "Nothing to repair — every page Roe installed has a status."
    end
    redirect_to admin_root_path
  end

  private

  # Pages sorted for the index: by layout/navigation.md order when that file
  # exists, else alphabetically by title. Best-effort — a page is placed by its
  # public_url appearing among the nav's link hrefs; pages absent from the nav
  # fall to the end, alphabetically.
  def ordered_pages
    nav = navigation_order
    pages = Page.all.to_a
    if nav
      pages.sort_by { |p| [ nav.index(p.public_url) || nav.size, p.title.to_s.downcase ] }
    else
      pages.sort_by { |p| p.title.to_s.downcase }
    end
  end

  # Link hrefs from layout/navigation.md, in order — or nil when the file is
  # absent, so #ordered_pages falls back to alphabetical.
  def navigation_order
    path = File.join(RoeSitePaths::SITE_PATH, "layout", "navigation.md")
    return nil unless File.exist?(path)

    File.read(path).scan(/\]\(([^)]+)\)/).flatten.map(&:strip)
  end

  # Pages have a much smaller publish gate than posts: just audience
  # (when payments are configured) and any media files that don't
  # resolve. No published_to (pages don't go to newsletter), no
  # post-type-specific required fields.
  def build_publish_requirements(page)
    requirements = []

    if helpers.requires_audience_on_publish?
      requirements << {
        name: "audience",
        type: :radio,
        label: "Audience",
        hint: "Who should be able to see this page?",
        options: [
          [ "everyone", "Everyone", "Public content visible to all visitors" ],
          [ "paid", "Paid Members Only", "Only accessible to paid members" ]
        ],
        default: "everyone",
        current: page.metadata["audience"]
      }
    end

    page.missing_media_refs.each do |ref|
      requirements << {
        name: ref[:field],
        type: :text,
        label: ref[:field].humanize,
        hint: "File not found on disk — fix the path or upload the file.",
        current: ref[:path],
        missing_file: true
      }
    end

    requirements
  end

  # Page#member_page? believes a declared page_type wherever the file lives, and
  # falls back to the members/ directory. Duplicating the path check here meant
  # a member page moved or renamed dropped out of the Member Pages group in the
  # index while still behaving as one everywhere else.
  def member_page?(page) = page.member_page?

  def sanitize_filename(filename)
    filename = filename.to_s.sub(/\.md$/, "")
    filename = File.basename(filename)
    filename.gsub(/[^a-zA-Z0-9\-_]/, "-")
            .gsub(/-+/, "-")
            .strip
            .gsub(/^-|-$/, "")
  end

  def filename_to_title(filename)
    name = filename.sub(/\.md$/, "")

    if name.match?(/[-_]/)
      name.split(/[-_]/).map(&:capitalize).join(" ")
    else
      name
    end
  end

  # nil-safe: the form's filename is optional now (it follows the title), so a
  # submission can arrive without one at all.
  def sanitize_filename(filename)
    filename = filename.to_s.sub(/\.md$/, "")
    return "" if filename.blank?

    File.basename(filename)
  end

  def update_page_status(page, new_status)
    content = File.read(page.file_path)
    parsed = FrontMatterParser::Parser.new(:md).call(content)

    metadata = parsed.front_matter.merge("status" => new_status)
    yaml_content = metadata.to_yaml.sub(/\A---\n/, "").strip
    new_content = "---\n#{yaml_content}\n---\n#{parsed.content}"

    normalize_and_write(page.file_path, new_content)
    ContentSync.sync_file(page.file_path)
  end

  def normalize_and_write(file_path, content)
    normalized = content.gsub(/\r\n/, "\n")
    SiteFile.write(file_path, normalized)
  end
end
