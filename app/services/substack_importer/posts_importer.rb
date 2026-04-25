# frozen_string_literal: true

module SubstackImporter
  class PostsImporter
    attr_reader :import, :stats, :errors

    def initialize(import)
      @import = import
      @stats = {
        posts_created: 0,
        posts_skipped: 0,
        media_downloaded: 0,
        media_reused: 0,
        missing_media: [],
        errors: []
      }
      @errors = []
    end

    def run
      @import.update!(status: :importing_posts, started_at: Time.current)

      Rails.logger.info "[SubstackImporter] Starting import #{@import.id}"
      Rails.logger.info "[SubstackImporter] Configuration: #{@import.configuration.inspect}"
      Rails.logger.info "[SubstackImporter] Filters: #{@import.filters.inspect}"
      Rails.logger.info "[SubstackImporter] Options: #{@import.options.inspect}"

      # Extract ZIP
      extract_path = extract_archive
      return false unless extract_path

      Rails.logger.info "[SubstackImporter] Extracted to: #{extract_path}"

      # List extracted files for debugging
      if Dir.exist?(extract_path)
        files = Dir.glob(File.join(extract_path, "**", "*")).select { |f| File.file?(f) }
        Rails.logger.info "[SubstackImporter] Extracted files: #{files.inspect}"
      end

      # Find the CSV file
      csv_path = find_csv_file(extract_path)
      unless csv_path
        Rails.logger.error "[SubstackImporter] No CSV file found in #{extract_path}"
        @import.mark_failed!("No CSV file found in export")
        return false
      end

      Rails.logger.info "[SubstackImporter] Using CSV: #{csv_path}"

      # Parse CSV
      begin
        csv_parser = CsvParser.new(csv_path)
        posts = csv_parser.parse
      rescue => e
        Rails.logger.error "[SubstackImporter] CSV parsing failed: #{e.message}"
        @import.mark_failed!("CSV parsing failed: #{e.message}")
        return false
      end

      Rails.logger.info "[SubstackImporter] Found #{posts.count} posts in CSV"

      if posts.empty?
        Rails.logger.warn "[SubstackImporter] No posts found in CSV!"
        @import.mark_failed!("No posts found in CSV")
        return false
      end

      # Filter posts
      filtered_posts = csv_parser.filter(
        drafts: @import.options["include_drafts"],
        type: @import.filters["type"],
        after: @import.filters["after"],
        before: @import.filters["before"]
      )

      Rails.logger.info "[SubstackImporter] After filtering: #{filtered_posts.count} posts"

      # Load HTML content
      posts_dir = find_posts_dir(extract_path)
      Rails.logger.info "[SubstackImporter] Looking for HTML in: #{posts_dir}"

      html_loader = HtmlLoader.new(posts_dir)
      html_loader.load
      match_result = html_loader.match_to_posts(filtered_posts)

      Rails.logger.info "[SubstackImporter] Matched #{match_result[:matched]} posts with HTML"

      if match_result[:unmatched_posts].any?
        Rails.logger.warn "[SubstackImporter] #{match_result[:unmatched_posts].count} posts without HTML"
        match_result[:unmatched_posts].each do |post|
          Rails.logger.warn "[SubstackImporter]   - #{post.slug} (ID: #{post.id})"
        end
      end

      # Fetch live data for cover images and podcast URLs
      # Only fetch for posts that don't already exist (to speed up re-imports)
      if @import.base_url.present?
        posts_needing_live_data = filtered_posts.reject do |post|
          ::Post.exists?([ "json_extract(metadata, '$.substack_post_id') = ?", post.id ])
        end

        if posts_needing_live_data.any?
          Rails.logger.info "[SubstackImporter] Fetching live data for #{posts_needing_live_data.count} new posts from #{@import.base_url}..."
          live_fetcher = LiveFetcher.new(base_url: @import.base_url, verbose: Rails.env.development?)
          live_fetcher.fetch_posts(posts_needing_live_data)

          if live_fetcher.manifest_entries.any?
            Rails.logger.warn "[SubstackImporter] #{live_fetcher.manifest_entries.count} posts with missing media from live fetch"
            @stats[:missing_media] ||= []
            live_fetcher.manifest_entries.each do |entry|
              @stats[:missing_media] << {
                slug: entry[:slug],
                items: [ { type: entry[:post_type], reason: entry[:reason] } ]
              }
            end
          end
        else
          Rails.logger.info "[SubstackImporter] All posts already exist, skipping live data fetch"
        end
      else
        Rails.logger.warn "[SubstackImporter] No base_url provided, skipping live data fetch"
      end

      # Setup media handler
      site_root = Rails.root.join("site").to_s
      media_handler = MediaHandler.new(
        site_root: site_root,
        import: @import,
        verbose: Rails.env.development?
      )

      # Setup frontmatter builder
      frontmatter = Frontmatter.new(
        site_root: site_root,
        default_published_to: @import.options["default_published_to"]
      )

      # Setup converter
      converter = Converter.new(
        verbose: Rails.env.development?,
        insert_paywalls: @import.options["insert_paywalls"] == "1",
        paywall_text: @import.options["paywall_text"].presence,
        paywall_button_text: @import.options["paywall_button_text"].presence
      )

      # Process each post
      processed_count = 0
      filtered_posts.each do |post|
        process_post(post, converter, frontmatter, media_handler)
        processed_count += 1
      end

      Rails.logger.info "[SubstackImporter] Processed #{processed_count} posts"
      Rails.logger.info "[SubstackImporter] Stats: #{@stats.inspect}"

      # Update stats
      @import.update!(
        status: :completed,
        stats: @import.stats.merge(@stats),
        completed_at: Time.current
      )

      # Complete phase 2
      @import.complete_phase!(2)

      # If no email list exists in the export, auto-complete phases 3 and 4
      # so the user doesn't have to step through them manually
      unless email_list_exists?
        Rails.logger.info "[SubstackImporter] No email list found, auto-completing phases 3 and 4"
        skipped_stats = {
          members_skipped_reason: "No email list found in export — member and delivery import skipped",
          deliveries_skipped_reason: "No email list found in export — member and delivery import skipped"
        }
        @import.update!(stats: @import.stats.merge(skipped_stats))
        @import.complete_phase!(3)
        @import.complete_phase!(4)
      end

      true
    rescue => e
      Rails.logger.error "[SubstackImporter] Import failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      @import.mark_failed!(e.message)
      false
    ensure
      # Cleanup extract directory
      if @extractor
        @extractor.cleanup
      end
    end

    def rollback
      return false unless @import.can_rollback?

      Rails.logger.info "[SubstackImporter] Rolling back import #{@import.id}"

      # Delete posts created by this import
      posts_deleted = @import.posts.count
      @import.posts.destroy_all

      # Delete media created by this import
      media_deleted = @import.media.count
      @import.media.find_each do |medium|
        # Delete file from disk
        full_path = Rails.root.join("site", medium.file_path.sub(%r{^/}, ""))
        FileUtils.rm_f(full_path) if File.exist?(full_path)
        medium.destroy
      end

      @import.update!(status: :rolled_back)

      Rails.logger.info "[SubstackImporter] Rollback complete: #{posts_deleted} posts, #{media_deleted} media files"

      { posts_deleted: posts_deleted, media_deleted: media_deleted }
    end

    private

    def extract_archive
      Rails.logger.info "[SubstackImporter] Archive path: #{@import.archive_path}"
      Rails.logger.info "[SubstackImporter] Extract path: #{@import.extract_path}"

      @extractor = Extractor.new(@import.archive_path, extract_path: @import.extract_path)
      result = @extractor.extract

      Rails.logger.info "[SubstackImporter] Extracted to: #{result}"
      result
    rescue => e
      Rails.logger.error "[SubstackImporter] Extraction failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      @errors << "Extraction failed: #{e.message}"
      @import.mark_failed!("Extraction failed: #{e.message}")
      nil
    end

    def process_post(post, converter, frontmatter, media_handler)
      # Check if post already exists (by substack_post_id)
      # Use ::Post to reference the Rails model, not SubstackImporter::Post struct
      existing = ::Post.find_by("json_extract(metadata, '$.substack_post_id') = ?", post.id)

      if existing
        Rails.logger.debug "[SubstackImporter] Post already exists: #{post.slug}"

        # Still ensure media exists (in case previous import was incomplete)
        # But don't track as "downloaded" for this import
        local_media = media_handler.download_post_media(post)

        # Track missing media for existing posts too
        if local_media[:missing].any?
          @stats[:missing_media] ||= []
          @stats[:missing_media] << { slug: post.slug, items: local_media[:missing] }
        end

        @stats[:posts_skipped] += 1
        return
      end

      # Convert HTML to Markdown
      markdown_body = converter.convert(post.html_content.to_s)

      # Download media for this post
      local_media = media_handler.download_post_media(post)
      @stats[:media_downloaded] += local_media[:images].count
      @stats[:media_downloaded] += 1 if local_media[:cover_image]
      @stats[:media_downloaded] += 1 if local_media[:audio]
      @stats[:media_downloaded] += 1 if local_media[:video]

      # For podcasts, extract real duration from the downloaded audio file.
      # This replaces the unreliable `podcast_duration` value from Substack
      # and matches what Roe's media-field controller does on user input.
      if post.type == "podcast" && local_media[:audio].present?
        audio_full_path = Rails.root.join("site", local_media[:audio].sub(%r{^/}, "")).to_s
        if File.exist?(audio_full_path)
          duration = MediaDurationExtractor.extract(audio_full_path)
          local_media[:duration] = duration if duration.present?
        end
      end

      # Track missing media
      if local_media[:missing].any?
        @stats[:missing_media] ||= []
        @stats[:missing_media] << { slug: post.slug, items: local_media[:missing] }
      end

      # Replace remote URLs with local paths
      markdown_body = media_handler.replace_urls(markdown_body)

      # Build frontmatter
      frontmatter_yaml = frontmatter.to_yaml(post, local_media: local_media)

      # Build file path
      file_path = build_file_path(post)

      # Ensure directory exists
      FileUtils.mkdir_p(File.dirname(file_path))

      # Write file
      content = "#{frontmatter_yaml}\n#{markdown_body}\n"
      File.write(file_path, content)

      # Create Post record via ContentSync
      # Use ::Post to reference the Rails model
      post_record = ::Post.create_or_update_from_file(file_path)

      if post_record.is_a?(::Post)
        post_record.update!(import: @import)
        @stats[:posts_created] += 1
        Rails.logger.info "[SubstackImporter] Created post: #{post.slug}"
      else
        @stats[:posts_skipped] += 1
        Rails.logger.warn "[SubstackImporter] Post creation returned warning for: #{post.slug}"
      end
    rescue => e
      Rails.logger.error "[SubstackImporter] Failed to process post #{post.slug}: #{e.message}"
      @stats[:errors] << "#{post.slug}: #{e.message}"
    end

    def build_file_path(post)
      base_path = if post.type == "page"
        Rails.root.join("site", "pages")
      else
        Rails.root.join("site", "posts")
      end

      # Posts go directly in /site/posts/ (no date subdirectories)
      File.join(base_path, "#{post.slug}.md")
    end

    def email_list_exists?
      extract_path = @import.extract_path
      return false unless extract_path.present? && Dir.exist?(extract_path)

      Dir.glob(File.join(extract_path, "email_list*.csv")).any?
    end

    def find_csv_file(extract_path)
      # First try the standard name
      standard_path = File.join(extract_path, "posts.csv")
      return standard_path if File.exist?(standard_path)

      # Otherwise find any CSV that looks like posts data
      csv_files = Dir.glob(File.join(extract_path, "*.csv"))
      Rails.logger.info "[SubstackImporter] Found CSV files: #{csv_files.inspect}"

      # Return the first CSV that contains posts or post data
      csv_files.find { |f| File.basename(f).match?(/post/i) } || csv_files.first
    end

    def find_posts_dir(extract_path)
      # First try the standard posts/ directory
      standard_dir = File.join(extract_path, "posts")
      return standard_dir if Dir.exist?(standard_dir)

      # Otherwise just use the extract root (files might be flat)
      extract_path
    end
  end
end
