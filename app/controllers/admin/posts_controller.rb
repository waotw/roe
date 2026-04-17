class Admin::PostsController < Admin::BaseController
  def index
    @posts = Post.order(Arel.sql("json_extract(metadata, '$.date') DESC NULLS LAST"))

    # Get all post types that exist in the database
    @existing_types = Post.pluck(Arel.sql("json_extract(metadata, '$.post_type')"))
                          .compact
                          .uniq

    @title = "Posts"
    @description = "All posts including drafts, published, and unlisted."
  end

  def drafts
    @posts = Post.draft.order(created_at: :desc)

    # Get distinct post types that exist (ADD THIS!)
    @existing_types = Post.distinct
      .pluck(Arel.sql("json_extract(metadata, '$.post_type')"))
      .compact
      .uniq

    render :index  # or whatever you're rendering
  end

  def unlisted
    @posts = Post.unlisted.order(Arel.sql("json_extract(metadata, '$.date') DESC NULLS LAST"))
    @title = "Unlisted Posts"
    @description = "Posts available at URL but not in feed."
    render :index
  end

  def preview
    @post = Post.find(params[:id])

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
      metadata['url_name'] ||= @post.metadata['url_name']

      @post.metadata = metadata
      @post.content = content
    end
    # GET = show saved version from database

    # ALWAYS set preview mode
    @preview_mode = true
    @preview_id = "post-#{@post.id}"

    render template: 'posts/show', layout: 'site'
  end

  def send_test_email
    @post = Post.find(params[:id])
    email = params[:email]

    unless email.present? && email.match?(URI::MailTo::EMAIL_REGEXP)
      render json: { success: false, error: 'Invalid email address' }
      return
    end

    unless helpers.newsletters_enabled?
      render json: { success: false, error: 'Newsletter feature is not enabled' }
      return
    end

    # Change to Postmark
    unless PostmarkConfig.configured?
      render json: { success: false, error: 'Postmark is not configured. Check Settings > Postmark.' }
      return
    end

    begin
      renderer = NewsletterRenderer.new(@post)
      html_content = renderer.render

      # Change to Postmark
      result = PostmarkService.send_transactional_email(
        to_email: email,
        to_name: email.split('@').first.titleize,
        subject: @post.title || 'Newsletter Preview',
        html_content: html_content,
        tag: 'test-newsletter'
      )

      if result[:success]
        render json: { success: true }
      else
        render json: { success: false, error: result[:error] || 'Failed to send email' }
      end

    rescue => e
      Rails.logger.error "Test email failed: #{e.message}"
      render json: { success: false, error: "Error: #{e.message}" }
    end
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

  #   # Create a temporary post object (not saved to DB)
  #   @post = Post.find(params[:id])

  #   # Override with preview content
  #   @post.define_singleton_method(:metadata) { metadata }
  #   @post.define_singleton_method(:content) { content }
  #   @post.define_singleton_method(:rendered_content) do
  #     MarkdownRenderer.render(content, metadata)
  #   end

  #   @preview_mode = true  # Add this line

  #   render template: 'posts/show', layout: 'site'
  # end

  def new
    @template = load_post_template
  end

  def create
    filename = sanitize_filename(params[:filename])
    file_path = Rails.root.join("site/posts/#{filename}.md")

    if File.exist?(file_path)
      flash.now[:error] = "A post with that filename already exists"
      @template = params[:content]
      @filename = filename
      render :new, status: :unprocessable_entity
      return
    end

    template_content = load_post_template
    title = filename_to_title(filename)

    parsed = FrontMatterParser::Parser.new(:md).call(template_content)
      metadata = parsed.front_matter.merge(
        "title" => title,
        "date" => Time.current.strftime("%Y-%m-%dT%H:%M")
      )

    # Ensure podcast GUID (if podcast type + published)
    metadata = ensure_podcast_guid(metadata, Post.new)

    if metadata['tags'].nil? || metadata['tags'] == ''
      metadata['tags'] = []
    end

    # Format YAML consistently for new posts
    yaml_content = Post.format_metadata_yaml(metadata)
    content = "---\n#{yaml_content}\n---\n#{parsed.content}"

    normalize_and_write(file_path, content)
    ContentSync.sync_file(file_path)

    post = Post.find_by(file_path: file_path.to_s)

    if post
      redirect_to edit_admin_post_path(post), notice: "Post created", flash: { new_post: true }
    else
      flash[:error] = "Post file created but failed to sync to database"
      redirect_to admin_posts_path
    end
  end

  def edit
    @post = Post.find(params[:id])
    raw_content = File.read(@post.file_path)

    begin
      parsed = FrontMatterParser::Parser.new(:md).call(raw_content)

      # Convert hash to YAML without document separator
      @metadata = parsed.front_matter.to_yaml.sub(/\A---\n/, '')
      @content = parsed.content

    rescue Psych::SyntaxError, StandardError => e
      # First attempt: Try to fix GUID specifically
      if Post.fix_guid_in_file(@post.file_path)
        # Reload and try again
        raw_content = File.read(@post.file_path)

        begin
          parsed = FrontMatterParser::Parser.new(:md).call(raw_content)
          @metadata = parsed.front_matter.to_yaml.sub(/\A---\n/, '')
          @content = parsed.content

          flash.now[:notice] = "Auto-fixed malformed GUID formatting"

        rescue => e2
          # Still broken - show fallback
          handle_broken_yaml(raw_content, e2)
        end
      else
        # GUID fix didn't apply - show fallback
        handle_broken_yaml(raw_content, e)
      end
    end

    @preview_path = preview_admin_post_path(@post)

    # Calculate new members count for newsletter status
    calculate_new_members_count
  end

  def update
    @post = Post.find(params[:id])

    metadata_yaml = params[:metadata_final].presence || params[:metadata]

    begin
      # Validate it's valid YAML
      metadata = YAML.safe_load(metadata_yaml, permitted_classes: [ Date, Time, Symbol ])

      unless metadata.is_a?(Hash)
        raise "Metadata must be key-value pairs"
      end

      # Remove the error flag if it exists (YAML is now fixed)
      metadata.delete('_yaml_parse_error')

      if metadata['tags'].is_a?(String)
        if metadata['tags'].strip.empty? || metadata['tags'] == '[]'
          metadata['tags'] = []
        else
          metadata['tags'] = metadata['tags'].split(',').map(&:strip).reject(&:empty?)
        end
      elsif metadata['tags'].nil?
        metadata['tags'] = []
      end

      # Ensure podcast GUID (if podcast type + published)
      metadata = ensure_podcast_guid(metadata, @post)

      # Re-serialize to YAML after potential GUID modification
      yaml_content = Post.format_metadata_yaml(metadata)

    rescue => e
      flash[:warning] = "YAML warning: #{e.message}. File saved anyway."
      full_content = "---\n#{metadata_yaml}\n---\n#{params[:content]}"
      normalize_and_write(@post.file_path, full_content)
      redirect_to edit_admin_post_path(@post)
      return
    end

    # Use the formatted YAML (includes GUID if added/restored)
    full_content = "---\n#{yaml_content}\n---\n#{params[:content]}"
    normalize_and_write(@post.file_path, full_content)

    ContentSync.sync_file(@post.file_path)

    flash[:notice] = "Post saved"

    redirect_to edit_admin_post_path(@post)
  end

  def rename
    @post = Post.find(params[:id])
    new_filename = sanitize_filename(params[:new_filename])

    if new_filename.blank?
      flash[:error] = "Filename cannot be empty"
      redirect_to admin_posts_path and return
    end

    old_path = Pathname.new(@post.file_path)
    new_path = old_path.dirname.join("#{new_filename}.md")

    if File.exist?(new_path) && new_path != old_path
      flash[:error] = "A file with that name already exists"
      redirect_to admin_posts_path and return
    end

    begin
      File.rename(old_path, new_path)
      @post.update(file_path: new_path.to_s)
      ContentSync.sync_file(new_path)

      flash[:notice] = "Renamed to #{new_filename}.md"
    rescue => e
      flash[:error] = "Failed to rename: #{e.message}"
    end

    redirect_to admin_posts_path
  end

  def resend_newsletter
    @post = Post.find(params[:id])

    # Find last send time
    last_send = NewsletterSend.where(post: @post).maximum(:sent_at)

    unless last_send
      flash[:error] = "This newsletter hasn't been sent yet"
      redirect_to edit_admin_post_path(@post) and return
    end

    # Find new members who joined after last send
    new_members = Member.newsletter_subscribed
                        .active
                        .where('subscribed_at > ?', last_send)

    # If this is a Substack-imported post, exclude Substack-imported members
    if @post.metadata['substack_post_id'].present?
      new_members = new_members.where(import_id: nil)  # ← Fixed: was @new_members
    end

    # Filter by audience if needed
    new_members = new_members.paid_tier if @post.audience == 'paid'

    if new_members.empty?
      flash[:notice] = "No new members to send to"
      redirect_to edit_admin_post_path(@post) and return
    end

    # Queue newsletter sending job
    QueueNewsletterBatchesJob.perform_later(@post.id, new_members.pluck(:id))

    flash[:notice] = "Newsletter queued for #{new_members.count} new #{'member'.pluralize(new_members.count)}"
    redirect_to edit_admin_post_path(@post)
  end

  def confirm_resend
    @post = Post.find(params[:id])

    # Find last send time
    last_send = NewsletterSend.where(post: @post).maximum(:sent_at)

    unless last_send
      flash[:error] = "This newsletter hasn't been sent yet"
      redirect_to edit_admin_post_path(@post) and return
    end

    # Find members who haven't received this newsletter yet
    received_member_ids = NewsletterSend.where(post: @post).pluck(:member_id)
    new_members = Member.newsletter_subscribed
                        .active
                        .where.not(id: received_member_ids)

    # If this is a Substack-imported post, exclude Substack-imported members
    if @post.metadata['substack_post_id'].present?
      new_members = new_members.where(import_id: nil)  # ← Fixed: was @new_members, also moved before audience filter
    end

    # Filter by audience if needed
    new_members = new_members.paid_tier if @post.audience == 'paid'

    if new_members.empty?
      flash[:notice] = "No new members to send to"
      redirect_to edit_admin_post_path(@post) and return
    end

    # Queue newsletter sending job
    QueueNewsletterBatchesJob.perform_later(@post.id, new_members.pluck(:id))

    head :ok
  end

  def resend_modal
    @post = Post.find(params[:id])

    # Find last send time (for display purposes)
    last_send = NewsletterSend.where(post: @post).maximum(:sent_at)

    unless last_send
      flash[:error] = "This newsletter hasn't been sent yet"
      redirect_to edit_admin_post_path(@post) and return
    end

    # Find members who haven't received this newsletter yet
    received_member_ids = NewsletterSend.where(post: @post).pluck(:member_id)
    @new_members = Member.newsletter_subscribed
                         .active
                         .where.not(id: received_member_ids)
                         .order(subscribed_at: :desc)

    # Filter by audience if needed
    @new_members = @new_members.paid_tier if @post.audience == 'paid'

    # If this is a Substack-imported post, exclude Substack-imported members
    if @post.metadata['substack_post_id'].present?
      @new_members = @new_members.where(import_id: nil)
    end

    @new_members_count = @new_members.count

    if @new_members_count == 0
      flash[:notice] = "No new members to send to"
      redirect_to edit_admin_post_path(@post) and return
    end

    render partial: 'resend_modal', layout: false
  end

  def newsletter_status
    @post = Post.find(params[:id])
    calculate_new_members_count
    render partial: 'newsletter_status', layout: false
  end

  def destroy
    @post = Post.find(params[:id])
    file_path = @post.file_path

    begin
      # Delete the file from site/posts/
      File.delete(file_path) if File.exist?(file_path)

      # Delete the database record
      @post.destroy

      flash[:notice] = "Post deleted successfully"
    rescue => e
      flash[:error] = "Failed to delete post: #{e.message}"
    end

    redirect_to admin_posts_path
  end

  def publish
    @post = Post.find(params[:id])
    update_post_status(@post, 'published')
    flash[:notice] = "Post published"
    redirect_to edit_admin_post_path(@post)
  end

  def publish_modal
    @post = Post.find(params[:id])
    @requires_audience = params[:requires_audience] == 'true'
    @requires_published_to = params[:requires_published_to] == 'true'
    @current_audience = params[:current_audience].presence
    @current_published_to = params[:current_published_to].presence

    render partial: 'publish_modal', layout: false
  end

  def confirm_publish
    @post = Post.find(params[:id])

    # Read current content
    raw_content = File.read(@post.file_path)
    parsed = FrontMatterParser::Parser.new(:md).call(raw_content)
    metadata = parsed.front_matter

    # Update metadata
    metadata['status'] = 'published'
    metadata['audience'] = params[:audience] if params[:audience].present?
    metadata['published_to'] = params[:published_to] if params[:published_to].present?

    # Write back to file
    yaml_content = Post.format_metadata_yaml(metadata)
    full_content = "---\n#{yaml_content}\n---\n#{parsed.content}"
    normalize_and_write(@post.file_path, full_content)

    # Sync to DB
    ContentSync.sync_file(@post.file_path)
    @post.reload

    # Send newsletter if published_to includes newsletter
    if should_send_newsletter?(@post)
      # Queue background job instead of sending immediately
      QueueNewsletterBatchesJob.perform_later(@post.id)
      flash[:notice] = "Post published. Newsletter is being sent in the background."
    else
      flash[:notice] = "Post published"
    end

    # Always redirect - this ensures the modal closes and page refreshes
    redirect_to edit_admin_post_path(@post), status: :see_other
  end

  def unpublish
    @post = Post.find(params[:id])
    update_post_status(@post, 'draft')
    flash[:notice] = "Post unpublished"
    redirect_to edit_admin_post_path(@post)
  end

  def search
    query = params[:q].to_s.downcase

    posts = Post.where("json_extract(metadata, '$.status') = 'published'")
                .where("LOWER(json_extract(metadata, '$.title')) LIKE ?", "%#{query}%")
                .limit(10)

    results = posts.map do |post|
      {
        id: post.id,
        title: post.title,  # This uses the Post model's title method which extracts from metadata
        url_name: post.url_name,
        url: "/posts/#{post.url_name}",
        metadata: post.metadata
      }
    end

    render json: results
  rescue => e
    Rails.logger.error "Post search error: #{e.message}"
    render json: { error: e.message }, status: :internal_server_error
  end

  private

  def calculate_new_members_count
    # Calculate new members count with same logic as resend_modal
    if @post.persisted? && NewsletterSend.exists?(post: @post)
      received_member_ids = NewsletterSend.where(post: @post).pluck(:member_id)
      new_members = Member.newsletter_subscribed
                          .active
                          .where.not(id: received_member_ids)

      # Filter by audience if needed
      new_members = new_members.paid_tier if @post.audience == 'paid'

      # If this is a Substack-imported post, exclude Substack-imported members
      if @post.metadata['substack_post_id'].present?
        new_members = new_members.where(import_id: nil)
      end

      @new_members_count = new_members.count
    else
      @new_members_count = 0
    end
  end

  def should_send_newsletter?(post)
    published_to = post.metadata['published_to'] || post.published_to
    published_to.in?([ 'newsletter', 'both' ])
  end

  def send_newsletter(post)
    sender = NewsletterSender.new(post)
    sender.send_to_audience
  rescue => e
    Rails.logger.error "Newsletter send failed: #{e.message}"
    { success: false, error: e.message }
  end

  def ensure_podcast_guid(metadata_hash, post)
    # Only process for podcast posts
    return metadata_hash unless metadata_hash['post_type'] == 'podcast'

    # Only process if status is published
    return metadata_hash unless metadata_hash['status'] == 'published'

    # If this is an existing published podcast with a GUID in the database
    if post.persisted?
      existing_guid = post.metadata['guid']

      if existing_guid.present?
        # ALWAYS restore the database GUID (prevents editing/deletion)
        if metadata_hash['guid'] != existing_guid
          metadata_hash['guid'] = existing_guid
          Rails.logger.warn "🔒 Restored immutable GUID for '#{metadata_hash['title']}'"
        end
        return metadata_hash  # GUID is set and immutable
      end
    end

    # No existing GUID - generate one (first publish)
    if metadata_hash['guid'].blank?
      metadata_hash['guid'] = SecureRandom.uuid
      Rails.logger.info "✨ Generated new GUID for '#{metadata_hash['title']}'"
    end

    metadata_hash
  end

  def handle_broken_yaml(raw_content, error)
    Rails.logger.error "Failed to parse file for editing: #{error.message}"

    # Extract content body if possible
    if raw_content =~ /\A---\s*\n.*?\n---\s*\n(.*)/m
      @content = $1
    else
      @content = raw_content
    end

    # Use metadata from database (last known good state) and add error flag
    db_metadata = @post.metadata.dup
    db_metadata['_yaml_parse_error'] = error.message
    @metadata = db_metadata.to_yaml.sub(/\A---\n/, '')

    flash.now[:alert] = "YAML parsing error detected. The form shows the last valid metadata from the database. Saving will fix the file formatting."
  end

  def sanitize_filename(filename)
    filename = filename.to_s.sub(/\.md$/, '')
    filename = File.basename(filename)
    filename.gsub(/[^a-zA-Z0-9\-_]/, '-')
            .gsub(/-+/, '-')
            .strip
            .gsub(/^-|-$/, '')
  end

  def load_post_template
    template_path = Rails.root.join("site/templates/post_template.md")

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
      post_type: article
      tags:
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

    # Extract frontmatter and body
    if content =~ /\A---\s*\n(.*?)\n---\s*\n(.*)/m
      yaml_content = $1
      body_content = $2

      # Parse to update status
      metadata = YAML.safe_load(yaml_content, permitted_classes: [ Date, Time, Symbol ])
      metadata['status'] = new_status

      # Re-format with consistent style
      new_yaml = Post.format_metadata_yaml(metadata)
      new_content = "---\n#{new_yaml}\n---\n#{body_content}"

      normalize_and_write(post.file_path, new_content)
      ContentSync.sync_file(post.file_path)
    end
  end

  def normalize_and_write(file_path, content)
    normalized = content.gsub(/\r\n/, "\n")
    File.write(file_path, normalized)
  end
end
