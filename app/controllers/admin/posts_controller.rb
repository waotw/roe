class Admin::PostsController < Admin::BaseController
  def index
    @posts = Post.order(Arel.sql("json_extract(metadata, '$.date') DESC NULLS LAST"))
    @title = "Posts"
    @description = "All posts including drafts, published, and unlisted."
  end

  def drafts
    @posts = Post.drafts.order(Arel.sql("json_extract(metadata, '$.date') DESC NULLS LAST"))
    @title = "Drafts"
    @description = "Posts that haven't been published yet."
    render :index
  end

  def unlisted
    @posts = Post.unlisted.order(Arel.sql("json_extract(metadata, '$.date') DESC NULLS LAST"))
    @title = "Unlisted Posts"
    @description = "Posts available at URL but not in feed."
    render :index
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
    @post = Post.find(params[:id])

    # Override with preview content
    @post.define_singleton_method(:metadata) { metadata }
    @post.define_singleton_method(:content) { content }
    @post.define_singleton_method(:rendered_content) do
      MarkdownRenderer.render(content, metadata)
    end

    render template: 'posts/show', layout: 'site'
  end

  def new
    @template = load_post_template
  end

  def create
    filename = sanitize_filename(params[:filename])
    file_path = Rails.root.join("content/posts/#{filename}.md")

    if File.exist?(file_path)
      flash[:error] = "A post with that filename already exists"
      @template = params[:content]
      render :new
      return
    end

    # Load template and populate title from filename
    template_content = load_post_template
    title = filename_to_title(filename)

    # Parse template and update title
    parsed = FrontMatterParser::Parser.new(:md).call(template_content)
    metadata = parsed.front_matter.merge("title" => title)

    yaml_content = metadata.to_yaml.sub(/\A---\n/, '').strip
      content = "---\n#{yaml_content}\n---\n#{parsed.content}"

    normalize_and_write(file_path, content)

    # Manually sync the file immediately (don't wait for file watcher)
    ContentSync.sync_file(file_path)

    post = Post.find_by(file_path: file_path.to_s)

    if post
      redirect_to edit_admin_post_path(post)
    else
      flash[:error] = "Post file created but failed to sync to database"
      redirect_to admin_posts_path
    end
  end

  def edit
    @post = Post.find(params[:id])
    raw_content = File.read(@post.file_path)

    parsed = FrontMatterParser::Parser.new(:md).call(raw_content)

    # Convert hash to YAML without document separator
    @metadata = parsed.front_matter.to_yaml.sub(/\A---\n/, '')
    @content = parsed.content
    @preview_path = preview_admin_post_path(@post)
  end

  def update
    @post = Post.find(params[:id])

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
      # Save as-is even with invalid YAML
      full_content = "---\n#{params[:metadata]}\n---\n#{params[:content]}"
      normalize_and_write(@post.file_path, full_content)

      @metadata = params[:metadata]
      @content = params[:content]
      render :edit
      return
    end

    # Valid YAML - reconstruct properly
    yaml_content = metadata.to_yaml.sub(/\A---\n/, '').strip
    full_content = "---\n#{yaml_content}\n---\n#{params[:content]}"
    full_content = full_content.gsub(/\r\n/, "\n")
    normalize_and_write(@post.file_path, full_content)

    ContentSync.sync_file(@post.file_path)

    flash[:notice] = "Post saved"
    flash[:trigger_refresh] = true

    @raw_content = full_content
    @metadata = metadata.to_yaml.strip
    @content = params[:content]
    @preview_path = preview_admin_post_path(@post)
    render :edit
  end

  def publish
    @post = Post.find(params[:id])
    update_post_status(@post, 'published')
    flash[:notice] = "Post published"
    redirect_to edit_admin_post_path(@post)
  end

  def unpublish
    @post = Post.find(params[:id])
    update_post_status(@post, 'draft')
    flash[:notice] = "Post unpublished"
    redirect_to edit_admin_post_path(@post)
  end

  private

  def load_post_template
    template_path = Rails.root.join("content/templates/post_template.md")

    if File.exist?(template_path)
      File.read(template_path)
    else
      # Default template if file doesn't exist
      default_template
    end
  end

  def default_template
    <<~TEMPLATE
      ---
      title:
      date: #{Date.today}
      status: draft
      type: article
      ---

      Start writing...
    TEMPLATE
  end

  def filename_to_title(filename)
    # Remove .md extension if present
    name = filename.sub(/\.md$/, '')

    # If filename has dashes or underscores, convert to title case
    if name.match?(/[-_]/)
      name.split(/[-_]/).map(&:capitalize).join(' ')
    else
      # Keep original capitalization
      name
    end
  end

  def sanitize_filename(filename)
    # Remove .md if they added it
    filename = filename.sub(/\.md$/, '')
    # Remove any path traversal attempts
    File.basename(filename)
  end

  def update_post_status(post, new_status)
    content = File.read(post.file_path)
    parsed = FrontMatterParser::Parser.new(:md).call(content)

    metadata = parsed.front_matter.merge("status" => new_status)
    yaml_content = metadata.to_yaml.sub(/\A---\n/, '').strip  # Add this line
    new_content = "---\n#{yaml_content}\n---\n#{parsed.content}"  # Use yaml_content

    normalize_and_write(@post.file_path, new_content)
    ContentSync.sync_file(post.file_path)
  end

  def normalize_and_write(file_path, content)
    normalized = content.gsub(/\r\n/, "\n")
    File.write(file_path, normalized)
  end
end
