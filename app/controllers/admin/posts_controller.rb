class Admin::PostsController < Admin::BaseController
  include BulkContentActions
  include CreatesContent

  # Bulk-action wiring (see BulkContentActions).
  def bulk_model = Post
  def bulk_index_path = admin_posts_path
  def bulk_label = "post"
  def prepare_publish_metadata(record, metadata) = ensure_podcast_guid(metadata, record)

  def bulk_publish_side_effect(record)
    return false unless should_send_newsletter?(record)
    QueueNewsletterBatchesJob.perform_later(record.id)
    true
  end
  layout -> { action_name == "edit" ? "editor" : "admin" }

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
      metadata["url_name"] ||= @post.metadata["url_name"]

      @post.metadata = metadata
      @post.content = content
    end
    # GET = show saved version from database

    # ALWAYS set preview mode
    @preview_mode = true
    @preview_id = "post-#{@post.id}"

    # Podcast episodes need their show config so the player can resolve show
    # artwork, subscribe links, etc. — mirror PostsController#show.
    if @post.post_type == "podcast" && @post.metadata["podcast"].present?
      @podcast_config = PodcastConfig.get(@post.metadata["podcast"])
      @podcast_episodes = Post
        .published
        .where("json_extract(metadata, '$.post_type') = ?", "podcast")
        .where("json_extract(metadata, '$.podcast') = ?", @post.metadata["podcast"])
        .order(Arel.sql("json_extract(metadata, '$.date') DESC"))
        .to_a
    end

    render template: "posts/show", layout: "site"
  end

  def send_test_email
    @post = Post.find(params[:id])
    email = params[:email]

    unless email.present? && email.match?(URI::MailTo::EMAIL_REGEXP)
      render json: { success: false, error: "Invalid email address" }
      return
    end

    unless helpers.newsletters_enabled?
      render json: { success: false, error: "Newsletter feature is not enabled" }
      return
    end

    # Change to Postmark
    unless PostmarkConfig.configured?
      render json: { success: false, error: "Postmark is not configured. Check Settings > Postmark." }
      return
    end

    begin
      renderer = NewsletterRenderer.new(@post)
      html_content = renderer.render

      # Change to Postmark
      result = PostmarkService.send_transactional_email(
        to_email: email,
        to_name: email.split("@").first.titleize,
        subject: @post.title || "Newsletter Preview",
        html_content: html_content,
        tag: "test-newsletter"
      )

      if result[:success]
        render json: { success: true }
      else
        render json: { success: false, error: result[:error] || "Failed to send email" }
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
    @template = ContentTemplate.template_content("post")
  end

  # Is this episode/track/chapter number (or url_name) already in use? Advisory
  # only — nothing here blocks a save; the writer is told and decides.
  def check_unique
    scopes = params[:scopes].respond_to?(:to_unsafe_h) ? params[:scopes].to_unsafe_h : {}
    conflict = Post.conflicting_post(
      field: params[:field],
      value: params[:value],
      scopes: scopes,
      exclude_url_name: params[:exclude]
    )

    render json: { taken: conflict.present?, conflict: conflict&.title }
  end

  def create
    title_param = params[:title].to_s.strip
    filename = sanitize_filename(params[:filename])

    # The two fields derive from each other: type a filename and the title
    # follows, or type only a title and the filename follows from it. Without
    # this a title-only submission wrote "posts/.md" — a dotfile, which
    # File.extname reads as having no extension, so the front matter parser
    # couldn't pick a syntax and died on nil.to_sym.
    filename = sanitize_filename(title_param.parameterize) if filename.blank?

    if filename.blank?
      flash.now[:error] = "Give the post a filename or a title"
      render :new, status: :unprocessable_entity
      return
    end

    file_path = File.join(RoeSitePaths::SITE_PATH, "posts/#{filename}.md")

    if File.exist?(file_path)
      flash.now[:error] = "A post with that filename already exists"
      @template = params[:content]
      @filename = filename
      render :new, status: :unprocessable_entity
      return
    end

    # The form's title field is optional — blank means "use the one derived
    # from the filename", which is what its placeholder was showing.
    title = title_param.presence || filename_to_title(filename)

    # post_type and the type's create fields come from the new-post form and go
    # straight into the frontmatter, so ContentScaffold can write a body that
    # actually works: a player that has audio to play, a track list that knows
    # which release to gather.
    overrides = { "title" => title }
    overrides["post_type"] = params[:post_type] if Post.post_type_options.include?(params[:post_type].to_s)
    overrides.merge!(create_field_overrides("post", post_type: overrides["post_type"]))

    # A track with no release still belongs somewhere: `singles`. Without it the
    # scaffold can't write a track list (an unfiltered one would gather every
    # track on the site), and singles would have no collection to appear in.
    if overrides["post_type"] == "music" && overrides["release"].blank?
      overrides["release"] = ReleaseConfig::DEFAULT_RELEASE
    end

    metadata, body = ContentTemplate.frontmatter_for("post", overrides)

    # Ensure podcast GUID (if podcast type + published)
    metadata = ensure_podcast_guid(metadata, Post.new)

    if metadata["tags"].nil? || metadata["tags"] == ""
      metadata["tags"] = []
    end

    # Format YAML consistently for new posts
    yaml_content = Post.format_metadata_yaml(metadata)
    content = "---\n#{yaml_content}\n---\n#{body}"

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
      @metadata = parsed.front_matter.to_yaml.sub(/\A---\n/, "")
      @content = parsed.content

    rescue Psych::SyntaxError, StandardError => e
      # First attempt: Try to fix GUID specifically
      if Post.fix_guid_in_file(@post.file_path)
        # Reload and try again
        raw_content = File.read(@post.file_path)

        begin
          parsed = FrontMatterParser::Parser.new(:md).call(raw_content)
          @metadata = parsed.front_matter.to_yaml.sub(/\A---\n/, "")
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
      metadata.delete("_yaml_parse_error")

      if metadata["tags"].is_a?(String)
        if metadata["tags"].strip.empty? || metadata["tags"] == "[]"
          metadata["tags"] = []
        else
          metadata["tags"] = metadata["tags"].split(",").map(&:strip).reject(&:empty?)
        end
      elsif metadata["tags"].nil?
        metadata["tags"] = []
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

    # Capture pre-save state so we can detect a publishing transition
    # (draft/unlisted → published) and queue any newsletter sends below.
    was_published = @post.published?

    # Use the formatted YAML (includes GUID if added/restored)
    full_content = "---\n#{yaml_content}\n---\n#{params[:content]}"
    normalize_and_write(@post.file_path, full_content)

    ContentSync.sync_file(@post.file_path)
    @post.reload

    # If this save published the post (transitioned from non-published)
    # and it's marked for newsletter delivery, queue the broadcast.
    just_published = !was_published && @post.published?
    if just_published && should_send_newsletter?(@post)
      QueueNewsletterBatchesJob.perform_later(@post.id)
      flash[:notice] = "Post published. Newsletter is being sent in the background."
    elsif just_published
      flash[:notice] = "Post published"
    else
      flash[:notice] = "Post saved"
    end

    redirect_to edit_admin_post_path(@post)
  end

  # Copy a post's file verbatim into a numbered sibling — same directory, an
  # incrementing "-N" suffix on the filename and " N" on the title (starting at
  # 2, skipping any that already exist). Everything else in the file is copied
  # as-is. Redirects into the editor for the new copy.
  def duplicate
    @post = Post.find(params[:id])
    raw = File.read(@post.file_path)
    parsed = FrontMatterParser::Parser.new(:md).call(raw)
    metadata = parsed.front_matter

    dir = Pathname.new(@post.file_path).dirname
    base_name = File.basename(@post.file_path, ".md").sub(/-\d+\z/, "")
    base_title = metadata["title"].to_s.sub(/\s+\d+\z/, "").strip

    n = 2
    n += 1 while File.exist?(dir.join("#{base_name}-#{n}.md"))
    new_path = dir.join("#{base_name}-#{n}.md")

    metadata["title"] = base_title.present? ? "#{base_title} #{n}" : "Untitled #{n}"
    yaml_content = Post.format_metadata_yaml(metadata)
    normalize_and_write(new_path, "---\n#{yaml_content}\n---\n#{parsed.content}")
    ContentSync.sync_file(new_path)

    new_post = Post.find_by(file_path: new_path.to_s)
    if new_post
      redirect_to edit_admin_post_path(new_post), notice: "Post duplicated"
    else
      redirect_to admin_posts_path, alert: "Duplicated the file but couldn't load the new post."
    end
  end

  def rename
    @post = Post.find(params[:id])
    new_filename = sanitize_filename(params[:new_filename])

    # Return to wherever the rename was submitted from — the editor passes its
    # own path as return_to (so it stays put), the index passes none and falls
    # back to the index. Only same-site absolute paths are allowed (no "//host"
    # or off-site URLs), so this can't be turned into an open redirect.
    return_to = lambda do
      target = params[:return_to].to_s
      safe = target.start_with?("/") && !target.start_with?("//")
      redirect_to(safe ? target : admin_posts_path, allow_other_host: false)
    end

    if new_filename.blank?
      flash[:error] = "Filename cannot be empty"
      return_to.call and return
    end

    old_path = Pathname.new(@post.file_path)
    new_path = old_path.dirname.join("#{new_filename}.md")

    if File.exist?(new_path) && new_path != old_path
      flash[:error] = "A file with that name already exists"
      return_to.call and return
    end

    begin
      File.rename(old_path, new_path)
      @post.update(file_path: new_path.to_s)
      ContentSync.sync_file(new_path)

      flash[:notice] = "Renamed to #{new_filename}.md"
    rescue => e
      flash[:error] = "Failed to rename: #{e.message}"
    end

    return_to.call
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
                        .where("subscribed_at > ?", last_send)

    # If this is a Substack-imported post, exclude Substack-imported members.
    # Belt-and-suspenders: import_id FK + durable metadata flag (the latter
    # survives if the Import record is ever deleted).
    if @post.metadata["substack_post_id"].present?
      new_members = new_members.where(import_id: nil).not_substack_imported
    end

    # Filter by audience if needed
    new_members = new_members.paid_tier if @post.audience == "paid"

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

    # If this is a Substack-imported post, exclude Substack-imported members.
    # Belt-and-suspenders: import_id FK + durable metadata flag.
    if @post.metadata["substack_post_id"].present?
      new_members = new_members.where(import_id: nil).not_substack_imported
    end

    # Filter by audience if needed
    new_members = new_members.paid_tier if @post.audience == "paid"

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
    @new_members = @new_members.paid_tier if @post.audience == "paid"

    # If this is a Substack-imported post, exclude Substack-imported members.
    # Belt-and-suspenders: import_id FK + durable metadata flag.
    if @post.metadata["substack_post_id"].present?
      @new_members = @new_members.where(import_id: nil).not_substack_imported
    end

    @new_members_count = @new_members.count

    if @new_members_count == 0
      flash[:notice] = "No new members to send to"
      redirect_to edit_admin_post_path(@post) and return
    end

    render partial: "resend_modal", layout: false
  end

  def newsletter_status
    @post = Post.find(params[:id])
    calculate_new_members_count
    render partial: "newsletter_status", layout: false
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

  def publish_modal
    @post = Post.find(params[:id])

    # If the editor sent its current form-state metadata, swap it in on
    # the in-memory post before computing requirements. This makes the
    # modal reflect what the user is *about to publish* (e.g. a just-
    # changed post_type that hasn't been saved yet) rather than the
    # last-synced file state.
    if params[:metadata].present?
      begin
        submitted = YAML.safe_load(params[:metadata], permitted_classes: [ Date, Time, Symbol ])
        @post.metadata = submitted if submitted.is_a?(Hash) && submitted.any?
      rescue => e
        Rails.logger.warn "publish_modal: ignoring unparseable submitted metadata (#{e.message})"
      end
    end

    @missing_requirements = build_publish_requirements(@post)
    # Present title/date → read-only "✓" confirmation bullets (audience and
    # distribution stay explicit radios in @missing_requirements).
    @present_requirements = %w[title date]
      .select { |name| @post.metadata[name].to_s.strip.present? }
      .map { |name| { name: name, label: name.humanize, value: @post.metadata[name] } }
    @resource_label = "Post"
    @show_postmark_warning = helpers.newsletters_enabled? && !helpers.postmark_configured?

    # Pair audio/video with duration so the modal can extract duration into
    # the matching field client-side. The paired duration is nested, so we
    # strip it from the top-level list to avoid rendering it twice.
    media_section = @missing_requirements.find { |r| %w[audio video].include?(r[:name]) }
    duration_section = @missing_requirements.find { |r| r[:name] == "duration" }
    @paired_duration_for = nil
    if media_section && duration_section
      @paired_duration_for = media_section[:name]
      @missing_requirements -= [ duration_section ]
      @paired_duration = duration_section
    end

    render partial: "publish_modal", layout: false
  end

  def unpublish
    @post = Post.find(params[:id])
    update_post_status(@post, "draft")
    flash[:notice] = "Post unpublished"
    redirect_to edit_admin_post_path(@post)
  end

  # Client-side duration backfill (episode_durations controller reads the
  # audio/video metadata in the browser and posts it here). Only fills a blank
  # value — never clobbers a real one.
  def set_duration
    post = Post.find(params[:id])
    duration = params[:duration].to_s.strip

    return head :unprocessable_entity unless duration.match?(/\A\d{1,3}:\d{2}(:\d{2})?\z/)
    return head :no_content if post.metadata["duration"].to_s.strip.present?

    write_metadata_field(post, "duration", duration)
    head :ok
  end

  def search
    query = params[:q].to_s.downcase
    title_match = "%#{query}%"

    posts = Post.where("json_extract(metadata, '$.status') = 'published'")
                .where("LOWER(json_extract(metadata, '$.title')) LIKE ?", title_match)
                .limit(8)
    pages = Page.where("json_extract(metadata, '$.status') = 'published'")
                .where("LOWER(json_extract(metadata, '$.title')) LIKE ?", title_match)
                .limit(5)
    products = Product.where("json_extract(metadata, '$.status') = 'published'")
                      .where("LOWER(json_extract(metadata, '$.title')) LIKE ?", title_match)
                      .limit(5)
    docs = Documentation.where("json_extract(metadata, '$.status') = 'published'")
                        .where("LOWER(json_extract(metadata, '$.title')) LIKE ?", title_match)
                        .where("file_path NOT LIKE '%/roe/%'")
                        .limit(5)

    results = posts.map { |r| { id: r.id, title: r.title, url_name: r.url_name, url: "/posts/#{r.url_name}", type: "Post" } } +
              pages.map { |r| { id: r.id, title: r.title, url_name: r.url_name, url: r.public_url, type: "Page" } } +
              products.map { |r| { id: r.id, title: r.title, url_name: r.url_name, url: "/store/#{r.url_name}", type: "Product" } } +
              docs.map { |r| { id: r.id, title: r.title, url_name: r.url_name, url: "/documentation/#{r.url_name}", type: "Doc" } }

    render json: results
  rescue => e
    Rails.logger.error "Post search error: #{e.message}"
    render json: { error: e.message }, status: :internal_server_error
  end

  # The values a post-link card would inherit from `params[:post]` (title,
  # excerpt, author, date, image, url, subtitle) — the card builder shows them
  # as live placeholders on the override fields. Returns {} when unresolved.
  def card_fields
    fields = PostLinkPreview.for(params[:post])
    render json: fields || {}
  rescue => e
    Rails.logger.error "Post card_fields error: #{e.message}"
    render json: {}, status: :internal_server_error
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
      new_members = new_members.paid_tier if @post.audience == "paid"

      # If this is a Substack-imported post, exclude Substack-imported members.
      # Belt-and-suspenders: import_id FK + durable metadata flag.
      if @post.metadata["substack_post_id"].present?
        new_members = new_members.where(import_id: nil).not_substack_imported
      end

      @new_members_count = new_members.count
    else
      @new_members_count = 0
    end
  end

  def should_send_newsletter?(post)
    published_to = post.metadata["published_to"] || post.published_to
    published_to.in?([ "newsletter", "both" ])
  end

  def send_newsletter(post)
    sender = NewsletterSender.new(post)
    sender.send_to_audience
  rescue => e
    Rails.logger.error "Newsletter send failed: #{e.message}"
    { success: false, error: e.message }
  end

  # Returns an array of publish-time requirements that are blank on the post.
  # Each entry is a hash shaped for the publish modal to render:
  #   { name:, type:, label:, hint:, options:, current: }
  def build_publish_requirements(post)
    requirements = []

    # Title + date are required on every post. Missing → inputs here (date
    # prefilled with today, editable); present → read-only confirmation bullets
    # (see @present_requirements). Audience/distribution stay explicit radios.
    if post.metadata["title"].to_s.strip.blank?
      requirements << {
        name: "title",
        type: :text,
        label: "Title",
        hint: nil,
        current: post.metadata["title"]
      }
    end
    if post.metadata["date"].to_s.strip.blank?
      requirements << {
        name: "date",
        type: :date,
        label: "Date",
        hint: nil,
        current: Date.today.iso8601
      }
    end

    # Site-gated: audience (always shown when paid memberships are
    # configured, so the user confirms who the post is going to every
    # time they publish). Without payments, audience tiers are moot.
    if helpers.requires_audience_on_publish?
      requirements << {
        name: "audience",
        type: :radio,
        label: "Audience",
        hint: "Who should be able to see this post?",
        options: [
          [ "everyone", "Everyone", "Public content visible to all visitors" ],
          [ "paid", "Paid Members Only", "Only accessible to paid members" ]
        ],
        default: "everyone",
        current: post.metadata["audience"]
      }
    end

    # Site-gated: published_to (always shown when newsletters + postmark are
    # configured, so the user confirms where the post is being distributed).
    if helpers.requires_published_to_on_publish?
      requirements << {
        name: "published_to",
        type: :radio,
        label: "Distribution",
        hint: "Where should this post be published?",
        options: [
          [ "both", "Site & Newsletter", "Publish to site and send as newsletter" ],
          [ "site", "Site Only", "Publish to site, don't send newsletter" ],
          [ "newsletter", "Newsletter Only", "Send as newsletter, don't publish to site" ]
        ],
        default: "both",
        current: post.metadata["published_to"]
      }
    end

    # Type-specific requirements from POST_TYPES (blank required fields)
    post.missing_type_required_fields.each do |field|
      next if field[:name].to_s == "guid"  # auto-handled

      options = field[:options].respond_to?(:call) ? field[:options].call : field[:options]

      requirements << {
        name: field[:name].to_s,
        type: field[:type] || :text,
        label: field[:label] || field[:name].to_s.humanize,
        hint: field[:hint],
        options: options,
        current: post.metadata[field[:name].to_s]
      }
    end

    # Soft prompt: when a podcast post has no `podcast:` value yet, ask
    # which feed it should join (or explicitly pick "local-only"). The
    # field isn't strictly required — Substack-style "local-only" episodes
    # are a valid mode — but we want the writer to make the call once at
    # publish time rather than silently ship an unconnected episode.
    # Suppressed once the value is set so we don't re-prompt on every edit.
    if post.post_type == "podcast" && post.metadata["podcast"].to_s.strip.empty?
      feed_keys = PodcastConfig.podcast_keys
      if feed_keys.any?
        feed_options = feed_keys.map do |key|
          title = PodcastConfig.get(key)&.dig("title").to_s.strip.presence || key
          [ key, title, "Add this episode to the #{title} RSS feed" ]
        end
        feed_options << [ "", "Local-only", "This episode appears on the site but doesn't go out in any RSS feed" ]

        requirements << {
          name: "podcast",
          type: :radio,
          label: "Podcast feed",
          hint: "Which feed should this episode appear in?",
          options: feed_options,
          default: "",
          current: post.metadata["podcast"]
        }
      end
    end

    # Media files that are set in metadata but don't exist on disk. Surface
    # them in the modal so the user can fix a typo before the post goes live.
    already_listed = requirements.map { |r| r[:name] }
    post.missing_media_refs.each do |ref|
      next if already_listed.include?(ref[:field])

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

  # Music tracks get one too, on the same immutable terms. A GUID is what a
  # podcatcher dedupes on, so a release published as a feed needs every track
  # to keep the same one forever. Generating it for every published track —
  # not only those on a feed-enabled release — keeps it out of the way of the
  # feed switch: turning the feed on later would otherwise have to walk the
  # release and write a GUID into each track, and turning it off and on again
  # could hand subscribers a fresh set.
  def ensure_podcast_guid(metadata_hash, post)
    return metadata_hash unless Post::GUID_POST_TYPES.include?(metadata_hash["post_type"])

    # Only process if status is published
    return metadata_hash unless metadata_hash["status"] == "published"

    # If this is an existing published podcast with a GUID in the database
    if post.persisted?
      existing_guid = post.metadata["guid"]

      if existing_guid.present?
        # ALWAYS restore the database GUID (prevents editing/deletion)
        if metadata_hash["guid"] != existing_guid
          metadata_hash["guid"] = existing_guid
          Rails.logger.warn "🔒 Restored immutable GUID for '#{metadata_hash['title']}'"
        end
        return metadata_hash  # GUID is set and immutable
      end
    end

    # No existing GUID - generate one (first publish)
    if metadata_hash["guid"].blank?
      metadata_hash["guid"] = SecureRandom.uuid
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
    db_metadata["_yaml_parse_error"] = error.message
    @metadata = db_metadata.to_yaml.sub(/\A---\n/, "")

    flash.now[:alert] = "YAML parsing error detected. The form shows the last valid metadata from the database. Saving will fix the file formatting."
  end

  def sanitize_filename(filename)
    filename = filename.to_s.sub(/\.md$/, "")
    filename = File.basename(filename)
    filename.gsub(/[^a-zA-Z0-9\-_]/, "-")
            .gsub(/-+/, "-")
            .strip
            .gsub(/^-|-$/, "")
  end

  def filename_to_title(filename)
    # Remove .md extension if present
    name = filename.sub(/\.md$/, "")

    # If filename has dashes or underscores, convert to title case
    if name.match?(/[-_]/)
      name.split(/[-_]/).map(&:capitalize).join(" ")
    else
      # Keep original capitalization
      name
    end
  end

  def sanitize_filename(filename)
    # Remove .md if they added it
    filename = filename.sub(/\.md$/, "")
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
      metadata["status"] = new_status

      # Re-format with consistent style
      new_yaml = Post.format_metadata_yaml(metadata)
      new_content = "---\n#{new_yaml}\n---\n#{body_content}"

      normalize_and_write(post.file_path, new_content)
      ContentSync.sync_file(post.file_path)
    end
  end

  # Set a single frontmatter field on a post's file and re-sync.
  def write_metadata_field(post, key, value)
    content = File.read(post.file_path)
    return unless content =~ /\A---\s*\n(.*?)\n---\s*\n(.*)/m

    metadata = YAML.safe_load($1, permitted_classes: [ Date, Time, Symbol ]) || {}
    metadata[key] = value
    normalize_and_write(post.file_path, "---\n#{Post.format_metadata_yaml(metadata)}\n---\n#{$2}")
    ContentSync.sync_file(post.file_path)
  end

  def normalize_and_write(file_path, content)
    normalized = content.gsub(/\r\n/, "\n")
    SiteFile.write(file_path, normalized)
  end
end
