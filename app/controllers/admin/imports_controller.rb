class Admin::ImportsController < Admin::BaseController
  before_action :set_import, only: [ :show, :phase_2, :phase_2_run, :phase_3, :phase_3_run, :phase_4, :phase_4_run, :rollback, :rollback_members, :rollback_deliveries, :destroy, :resolve_missing_media, :attempt_download, :resolve_manually, :skip_missing_media, :reconnect_media, :retry_live_fetch ]

  def index
    @imports = Import.order(created_at: :desc)
  end

  def show
    # Show current status and progress
  end

  # Phase 1: Upload and Configure
  def new
    @import = Import.new
  end

  def create
    @import = Import.new
    @import.status = :pending
    @import.phase = 1
    @import.source_type = "substack"

    # Handle file upload
    if params[:import] && params[:import][:archive_file].present?
      uploaded_file = params[:import][:archive_file]

      # Ensure tmp/imports directory exists
      imports_dir = Rails.root.join("tmp", "imports")
      FileUtils.mkdir_p(imports_dir)

      # Save uploaded file
      file_name = "#{Time.current.to_i}_#{uploaded_file.original_filename}"
      file_path = imports_dir.join(file_name)

      File.open(file_path, "wb") do |f|
        f.write(uploaded_file.read)
      end

      @import.archive_file = file_name
    end

    if @import.save
      redirect_to phase_2_admin_import_path(@import)
    else
      render :new, status: :unprocessable_entity
    end
  end

  # Phase 2: Posts Import
  def phase_2
    # Show configuration and import form
  end

  def phase_2_run
    # Update configuration and clear any previous error
    @import.configuration = @import.configuration.merge(phase_2_params)
    @import.status = :importing_posts
    @import.started_at = Time.current
    @import.error_message = nil
    @import.save!

    # Start the import job
    ImportPostsJob.perform_later(@import.id)

    redirect_to admin_import_path(@import)
  end

  def rollback
    importer = SubstackImporter::PostsImporter.new(@import)
    result = importer.rollback

    if result
      redirect_to admin_import_path(@import), notice: "Import rolled back successfully. #{result[:posts_deleted]} posts and #{result[:media_deleted]} media files removed."
    else
      redirect_to admin_import_path(@import), alert: "Could not rollback import."
    end
  end

  def destroy
    # Clean up temp files first
    @import.cleanup_temp_files!

    # Delete the import record (this does NOT delete posts or media - just the tracking record)
    @import.destroy

    redirect_to admin_imports_path, notice: "Import record deleted. Posts and media remain in the system."
  end

  # Phase 3: Members Import
  def phase_3
    # Check if email list CSV exists. Prefer the extracted directory, but
    # fall back to peeking inside the archive ZIP (the extract dir may have
    # been cleaned up by an earlier version of the importer, or by hand).
    @has_email_list = email_list_in_extract? || email_list_in_archive?
  end

  def phase_3_run
    # Update options and clear any previous error
    @import.configuration = @import.configuration.merge(phase_3_params)
    @import.status = :importing_members
    @import.error_message = nil
    @import.save!

    # Start the members import job
    ImportMembersJob.perform_later(@import.id)

    redirect_to admin_import_path(@import)
  end

  def rollback_members
    importer = SubstackImporter::MembersImporter.new(@import)
    result = importer.rollback

    if result
      redirect_to admin_import_path(@import), notice: "Members rolled back successfully. #{result[:members_deleted]} members removed."
    else
      redirect_to admin_import_path(@import), alert: "Could not rollback members."
    end
  end

  # Phase 4: Deliveries Import
  def phase_4
    # Show confirmation page
  end

  def phase_4_run
    # Clear any previous error and start deliveries import
    @import.status = :importing_deliveries
    @import.error_message = nil
    @import.save!

    # Start the deliveries import job
    ImportDeliveriesJob.perform_later(@import.id)

    redirect_to admin_import_path(@import)
  end

  def rollback_deliveries
    importer = SubstackImporter::DeliveriesImporter.new(@import)
    result = importer.rollback

    if result
      redirect_to admin_import_path(@import), notice: "Deliveries rolled back successfully. #{result[:deliveries_deleted]} delivery records removed."
    else
      redirect_to admin_import_path(@import), alert: "Could not rollback deliveries."
    end
  end

  # Missing media resolution
  def resolve_missing_media
    @missing_items = @import.stats["missing_media"] || []

    # Check if any missing media now has Medium records (connected to posts)
    @missing_items.each do |entry|
      next if entry["resolved"] || entry["skipped"]

      item = entry["items"].first
      expected_path = item["expected_path"]

      # For old imports without expected_path, compute it from slug and type
      if expected_path.nil? || expected_path.empty?
        slug = entry["slug"]
        media_type = item["type"]

        case media_type
        when "image", "cover_image"
          ext = ".jpg"
          if item["url"].present?
            begin
              parsed_ext = File.extname(URI.parse(item["url"]).path).downcase
              ext = parsed_ext if parsed_ext.present? && parsed_ext.length > 1
            rescue URI::InvalidURIError
              # Use default
            end
          end
          expected_path = "/media/images/#{slug}-cover#{ext}"
        when "audio", "podcast"
          expected_path = "/media/audio/#{slug}.mp3"
        when "video"
          expected_path = "/media/video/#{slug}.mp4"
        else
          expected_path = "/media/images/#{slug}.jpg"
        end

        # Store computed path for future reference
        item["expected_path"] = expected_path
      end

      # Check if Medium record exists for this expected path
      if expected_path.present? && Medium.exists?(file_path: expected_path)
        entry["medium_exists"] = true
        entry["local_path"] = expected_path
      end
    end

    # Save computed paths back to import stats
    @import.save! if @import.stats_changed?
  end

  def attempt_download
    item_index = params[:item_index].to_i
    url = params[:url]

    missing_media = @import.stats["missing_media"] || []
    return redirect_to resolve_missing_media_admin_import_path(@import), alert: "Item not found" if item_index >= missing_media.length

    entry = missing_media[item_index]
    item = entry["items"].first

    # Determine media type and filename
    media_type = item["type"]
    slug = entry["slug"]

    # For old imports without expected_path, compute it and store it
    if item["expected_path"].nil? || item["expected_path"].empty?
      case media_type
      when "image", "cover_image"
        ext = File.extname(url).presence || ".jpg"
        item["expected_path"] = "/media/images/#{slug}-cover#{ext}"
        filename = "#{slug}-cover#{ext}"
        dest_dir = "images"
      when "audio", "podcast"
        item["expected_path"] = "/media/audio/#{slug}.mp3"
        filename = "#{slug}.mp3"
        dest_dir = "audio"
      when "video"
        item["expected_path"] = "/media/video/#{slug}.mp4"
        filename = "#{slug}.mp4"
        dest_dir = "video"
      else
        ext = File.extname(url).presence || ".bin"
        item["expected_path"] = "/media/images/#{slug}#{ext}"
        filename = "#{slug}#{ext}"
        dest_dir = "images"
      end
    else
      # Use existing expected_path to determine filename and dest_dir
      file_path = item["expected_path"]
      dest_dir = file_path.split("/")[2] # /media/audio/file.mp3 -> audio
      filename = File.basename(file_path)
    end

    dest_path = Rails.root.join("site", "media", dest_dir, filename)
    file_path = item["expected_path"]

    begin
      # Attempt download with redirect handling
      max_redirects = 5
      current_redirects = 0
      current_url = url
      download_success = false

      begin
        loop do
          uri = URI.parse(current_url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = 15
          # Longer timeout for video files
          http.read_timeout = media_type == "video" ? 300 : 120

          request = Net::HTTP::Get.new(uri)
          request["User-Agent"] = "Mozilla/5.0 (compatible; SubstackImporter)"

          response = http.request(request) do |resp|
            if resp.is_a?(Net::HTTPSuccess)
              # Write file in chunks for large files
              FileUtils.mkdir_p(File.dirname(dest_path))
              File.open(dest_path, "wb") do |file|
                resp.read_body do |chunk|
                  file.write(chunk)
                end
              end
              download_success = true
            elsif resp.is_a?(Net::HTTPRedirection)
              current_redirects += 1
              if current_redirects > max_redirects
                redirect_to resolve_missing_media_admin_import_path(@import), alert: "Download failed: Too many redirects"
                return
              end
              current_url = resp["location"]
              # Handle relative redirects
              current_url = URI.join(url, current_url).to_s unless current_url.start_with?("http")
            else
              redirect_to resolve_missing_media_admin_import_path(@import), alert: "Download failed: #{resp.code}"
              return
            end
          end

          # Break out of redirect loop if download succeeded
          break if download_success
        end

        # If we got here, download succeeded
        if download_success
          # Check if medium record already exists
          existing_medium = Medium.find_by(file_path: file_path)
          unless existing_medium
            # Create medium record
            Medium.create!(
              file_path: file_path,
              source_url: url,
              import: @import,
              uploaded_at: Time.current
            )
          end

          # Mark as resolved
          entry["resolved"] = true
          entry["local_path"] = file_path
          entry["downloaded"] = true
          entry["medium_exists"] = true
          @import.save!

          redirect_to resolve_missing_media_admin_import_path(@import), notice: "Downloaded and connected: #{filename} - Post frontmatter already references this path."
        end
      rescue => e
        # Check if file was partially downloaded and exists
        if File.exist?(dest_path) && File.size(dest_path) > 0
          # File exists, so mark as resolved even if there was an error
          existing_medium = Medium.find_by(file_path: file_path)
          unless existing_medium
            Medium.create!(
              file_path: file_path,
              source_url: url,
              import: @import,
              uploaded_at: Time.current
            )
          end

          entry["resolved"] = true
          entry["local_path"] = file_path
          entry["downloaded"] = true
          entry["medium_exists"] = true
          @import.save!

          redirect_to resolve_missing_media_admin_import_path(@import), notice: "Downloaded with warnings: #{filename} - Post frontmatter already references this path."
        else
          redirect_to resolve_missing_media_admin_import_path(@import), alert: "Download error: #{e.message}"
        end
      end
    end
  end

  def resolve_manually
    item_index = params[:item_index].to_i

    missing_media = @import.stats["missing_media"] || []
    return redirect_to resolve_missing_media_admin_import_path(@import), alert: "Item not found" if item_index >= missing_media.length

    entry = missing_media[item_index]
    item = entry["items"].first
    slug = entry["slug"]
    media_type = item["type"]
    expected_path = item["expected_path"]

    # For old imports without expected_path, compute it
    if expected_path.nil? || expected_path.empty?
      case media_type
      when "image", "cover_image"
        ext = ".jpg"
        if item["url"].present?
          begin
            parsed_ext = File.extname(URI.parse(item["url"]).path).downcase
            ext = parsed_ext if parsed_ext.present? && parsed_ext.length > 1
          rescue URI::InvalidURIError
          end
        end
        expected_path = "/media/images/#{slug}-cover#{ext}"
      when "audio", "podcast"
        expected_path = "/media/audio/#{slug}.mp3"
      when "video"
        expected_path = "/media/video/#{slug}.mp4"
      else
        expected_path = "/media/images/#{slug}.jpg"
      end

      item["expected_path"] = expected_path
    end

    # First check if Medium record already exists
    if Medium.exists?(file_path: expected_path)
      entry["resolved"] = true
      entry["medium_exists"] = true
      entry["local_path"] = expected_path
      @import.save!

      redirect_to resolve_missing_media_admin_import_path(@import), notice: "Already connected: #{expected_path}"
      return
    end

    # Fall back to pattern matching if expected path doesn't exist
    case media_type
    when "image", "cover_image"
      pattern = "#{slug}-cover.*"
      dest_dir = "images"
    when "audio", "podcast"
      pattern = "#{slug}.mp3"
      dest_dir = "audio"
    when "video"
      pattern = "#{slug}.mp4"
      dest_dir = "video"
    else
      pattern = "#{slug}*"
      dest_dir = "images"
    end

    # Check if file exists
    media_dir = Rails.root.join("site", "media", dest_dir)
    existing_files = Dir.glob(File.join(media_dir, pattern))

    if existing_files.any?
      file_path = "/media/#{dest_dir}/#{File.basename(existing_files.first)}"
      source_url = item["url"] || item["mux_id"] || "manual"

      # Check if medium record already exists
      existing_medium = Medium.find_by(file_path: file_path)

      if existing_medium.nil?
        # Create medium record only if it doesn't exist
        Medium.create!(
          file_path: file_path,
          source_url: source_url,
          import: @import,
          uploaded_at: File.mtime(existing_files.first)
        )
      end

      # Mark as resolved
      entry["resolved"] = true
      entry["medium_exists"] = true
      entry["local_path"] = file_path
      @import.save!

      redirect_to resolve_missing_media_admin_import_path(@import), notice: "Connected: #{File.basename(existing_files.first)} - The post frontmatter already references this file."
    else
      redirect_to resolve_missing_media_admin_import_path(@import), alert: "File not found. Please place the file at: #{expected_path}"
    end
  end

  def skip_missing_media
    item_index = params[:item_index].to_i
    reason = params[:reason].presence || "Skipped by user"

    missing_media = @import.stats["missing_media"] || []
    return redirect_to resolve_missing_media_admin_import_path(@import), alert: "Item not found" if item_index >= missing_media.length

    entry = missing_media[item_index]
    entry["skipped"] = true
    entry["skip_reason"] = reason
    @import.save!

    redirect_to resolve_missing_media_admin_import_path(@import), notice: "Skipped #{entry["slug"]}"
  end

  def reconnect_media
    verified = []
    reopened = []
    missing_media = @import.stats["missing_media"] || []

    # Check ALL entries, including already resolved ones (to re-verify)
    missing_media.each_with_index do |entry, index|
      # Skip explicitly skipped items
      next if entry["skipped"]

      item = entry["items"].first
      slug = entry["slug"]
      media_type = item["type"]
      expected_path = item["expected_path"]

      # For old imports without expected_path, compute it
      if expected_path.nil? || expected_path.empty?
        case media_type
        when "image", "cover_image"
          ext = ".jpg"
          if item["url"].present?
            begin
              parsed_ext = File.extname(URI.parse(item["url"]).path).downcase
              ext = parsed_ext if parsed_ext.present? && parsed_ext.length > 1
            rescue URI::InvalidURIError
            end
          end
          expected_path = "/media/images/#{slug}-cover#{ext}"
        when "audio", "podcast"
          expected_path = "/media/audio/#{slug}.mp3"
        when "video"
          expected_path = "/media/video/#{slug}.mp4"
        else
          expected_path = "/media/images/#{slug}.jpg"
        end

        item["expected_path"] = expected_path
      end

      disk_path = Rails.root.join("site", expected_path.sub(%r{^/}, ""))

      # Check if file exists on disk
      if File.exist?(disk_path)
        # Ensure Medium record exists
        unless Medium.exists?(file_path: expected_path)
          Medium.create!(
            file_path: expected_path,
            source_url: item["url"] || item["mux_id"] || "manual",
            import: @import,
            uploaded_at: File.mtime(disk_path)
          )
        end

        # Mark as resolved
        entry["resolved"] = true
        entry["medium_exists"] = true
        entry["local_path"] = expected_path
        verified << slug
      else
        # File doesn't exist - re-open this item for resolution
        was_resolved = entry["resolved"]
        entry["resolved"] = false
        entry["medium_exists"] = false
        entry["downloaded"] = false
        entry.delete("local_path")

        # Only count as "reopened" if it was previously marked as resolved
        reopened << slug if was_resolved
      end
    end

    @import.save!

    messages = []
    messages << "Verified #{verified.count} media connections" if verified.any?
    messages << "Re-opened #{reopened.count} missing media items" if reopened.any?

    if messages.any?
      redirect_to resolve_missing_media_admin_import_path(@import), notice: messages.join(". ")
    else
      # All skipped or no missing_media entries at all
      redirect_to resolve_missing_media_admin_import_path(@import), notice: "No media to verify (all items are skipped or none exist)"
    end
  end

  def retry_live_fetch
    missing_items = @import.stats["missing_media"] || []

    # Filter out already resolved or skipped items
    unresolved_items = missing_items.reject { |e| e["resolved"] || e["skipped"] }

    if unresolved_items.empty?
      redirect_to resolve_missing_media_admin_import_path(@import), notice: "No unresolved media items to fetch."
      return
    end

    # Extract unique post slugs from missing items
    post_slugs = unresolved_items.map { |e| e["slug"] }.uniq

    # Find the actual Post records by querying metadata->url_name
    posts_to_fetch = Post.where(import: @import).where(
      post_slugs.map { |slug| "json_extract(metadata, '$.url_name') = ?" }.join(" OR "),
      *post_slugs
    )

    if posts_to_fetch.empty?
      redirect_to resolve_missing_media_admin_import_path(@import), alert: "Could not find posts for missing media items."
      return
    end

    # Convert Post records back to SubstackImporter::Post structs for LiveFetcher
    # We need to recreate the struct with the necessary fields
    require "ostruct"
    fetcher_posts = posts_to_fetch.map do |post|
      OpenStruct.new(
        id: post.metadata["substack_post_id"],
        slug: post.url_name,
        title: post.title,
        type: post.post_type == "article" ? "newsletter" : post.post_type,
        audience: post.audience == "everyone" ? "free" : post.audience,
        is_published: post.published?,
        cover_image: post.image,
        podcast_url: post.audio,
        video_mux_playback_id: post.metadata["video_mux_playback_id"]
      )
    end

    # Run LiveFetcher on these posts
    base_url = @import.base_url
    if base_url.blank?
      redirect_to resolve_missing_media_admin_import_path(@import), alert: "No base URL configured. Please set a base URL in Phase 2."
      return
    end

    Rails.logger.info "[Admin::ImportsController] Retrying live fetch for #{fetcher_posts.count} posts with missing media"

    live_fetcher = SubstackImporter::LiveFetcher.new(base_url: base_url, verbose: Rails.env.development?)
    live_fetcher.fetch_posts(fetcher_posts)

    # Now attempt to download media with the updated URLs
    site_root = Rails.root.join("site").to_s
    media_handler = SubstackImporter::MediaHandler.new(
      site_root: site_root,
      import: @import,
      verbose: Rails.env.development?
    )

    frontmatter = SubstackImporter::Frontmatter.new(site_root: site_root)

    resolved_count = 0
    still_missing_count = 0

    fetcher_posts.each do |fetcher_post|
      # Download media for this post
      local_media = media_handler.download_post_media(fetcher_post)

      # Find the corresponding Post record
      post_record = posts_to_fetch.find { |p| p.url_name == fetcher_post.slug }
      next unless post_record

      # Update the post's frontmatter with new media paths
      file_path = Rails.root.join("site", "posts", "#{fetcher_post.slug}.md")
      next unless File.exist?(file_path)

      # Read current file
      content = File.read(file_path)

      # Extract body (everything after frontmatter)
      body = content.split(/^---\s*$/, 3)[2]&.strip || ""

      # Build new frontmatter with updated media
      new_frontmatter = frontmatter.to_yaml(fetcher_post, local_media: local_media)

      # Write updated file
      File.write(file_path, "#{new_frontmatter}\n#{body}\n")

      # Sync the post back to the database
      Post.create_or_update_from_file(file_path)

      # Update missing_media stats
      if local_media[:missing].empty?
        resolved_count += 1
        # Mark this entry as resolved in stats
        missing_items.each do |entry|
          if entry["slug"] == fetcher_post.slug
            entry["resolved"] = true
            entry["local_path"] = local_media[:cover_image] || local_media[:audio] || local_media[:video]
          end
        end
      else
        still_missing_count += 1
      end
    end

    # Save updated stats
    @import.stats["missing_media"] = missing_items
    @import.save!

    if resolved_count > 0
      redirect_to resolve_missing_media_admin_import_path(@import),
        notice: "Live fetch complete! Resolved #{resolved_count} items. #{still_missing_count} still need attention."
    else
      redirect_to resolve_missing_media_admin_import_path(@import),
        alert: "Live fetch complete, but could not resolve any items. URLs may still be unavailable."
    end
  end

  private

  def set_import
    @import = Import.find(params[:id])
  end

  def email_list_in_extract?
    extract_path = @import.extract_path
    extract_path.present? &&
      Dir.exist?(extract_path) &&
      Dir.glob(File.join(extract_path, "email_list*.csv")).any?
  end

  def email_list_in_archive?
    archive_path = @import.archive_path
    return false unless archive_path.present? && File.exist?(archive_path)

    Zip::File.open(archive_path) do |zip|
      zip.entries.any? { |e| File.basename(e.name).match?(/\Aemail_list.*\.csv\z/i) }
    end
  rescue => e
    Rails.logger.warn "[SubstackImporter] Could not peek into archive #{archive_path}: #{e.message}"
    false
  end

  def import_params
    # Only permit configuration as a hash - archive_file is handled separately
    params.require(:import).permit(configuration: {}).tap do |whitelisted|
      whitelisted[:configuration] ||= {}
    end
  end

  def phase_2_params
    params.require(:import).permit(
      :base_url,
      filters: {},
      options: {}
    ).tap do |whitelisted|
      whitelisted[:filters] ||= {}
      whitelisted[:options] ||= {}
    end
  end

  def phase_3_params
    params.require(:import).permit(
      options: [ :auto_gift_lifetime, :auto_gift_paid ]
    ).tap do |whitelisted|
      whitelisted[:options] ||= {}
    end
  end
end
